require 'yaml'
require 'json'
require 'kramdown'

class TocPage < Jekyll::Page
  # Initialize a new RedirectPage.
  #
  # site - The Site object.
  # base - The String path to the source.
  # dir  - The String path between the source and the file.
  # name - The String filename of the file.
  def initialize(site, base, dir, name, content)
    @site = site
    @base = base
    @dir = dir
    @name = name
    @content = @output = content

    self.process(name)
    self.data = {}
  end
end

class TocGenerator < Jekyll::Generator

  ITEM_TYPE_HEADER = 'header'
  ITEM_TYPE_PLACEHOLDER = 'placeholder'

  def generate(site)
    toc_input = site.config['toc_input'] || '_SUMMARY.md'
    toc_output = site.config['toc_output'] || 'HelpTOC.json'

    toc_content = generate_toc(site, toc_input)
    toc_page = TocPage.new(site, site.source, '/', toc_output, toc_content)
    site.pages << toc_page
  end

  def generate_toc(site, toc_input)

    toc = []
    content = File.read(File.join(site.source, toc_input))
    kramdown_config = site.config['kramdown'].merge({:html_to_native => true})
    kramdown_doc = Kramdown::Document.new(content, kramdown_config)

    kramdown_doc.root.children.each do |c|
      item = extract_from_node(c)
      toc.concat(item) if item != nil
    end

    # Removing headers of empty sections
    delete_list = []
    (0).upto(toc.length-1) do |i|
      item = toc[i]
      prev = toc[i-1] != nil ? toc[i-1] : nil
      item_is_header = (item[:type] != nil and item[:type] == ITEM_TYPE_HEADER)
      prev_is_header = (prev != nil and prev[:type] != nil and prev[:type] == ITEM_TYPE_HEADER)

      if item_is_header and prev_is_header
        delete_list.push(i-1)
      end
    end

    delete_list.each do |del_index|
      toc.delete_at(del_index)
    end

    toc.to_json
  end

  private
  def extract_from_node(node)
    items = []

    case node.type
      when :ul
        items.concat(extract_items(node))

      when :header
        items.push(extract_header(node)) if node.options[:level] == 2
    end

    return items.length > 0 ? items : nil
  end

  def extract_items(ul_node)
    items = []

    ul_node.children.select { |n| n.type == :li }.each do |li_node|
      items.push(extract_item(li_node))
    end

    return items
  end

  def extract_item(li_node)
    item = {}

    p = li_node.children[0]
    case p.children[0].type
      when :text
        item[:title] = p.children[0].value.strip
        item[:type] = ITEM_TYPE_PLACEHOLDER

      when :a
        a = p.children[0]
        href = a.attr['href']
        basename = href.chomp(File.extname(href)).sub(/^\//,'')
        href = basename + '.html'
        item[:id] = basename
        item[:title] = get_text(a.children)
        item[:url] = href
        is_external = href.start_with?('http://', 'https://', 'ftp://', '//')
        item[:is_external] = true if is_external
    end

    li_node.children.drop(1).each do |child|
      pages = extract_items(child) if child.type == :ul
      item[:pages] = pages if pages != nil
    end

    return item
  end

  def get_text(nodes)
    nodes.reduce('') { |t, c| t + format(c.value) }
  end

  def format(item)
    case item
      when Symbol
        Kramdown::Utils::Entities.entity(item.to_s).char
      when String
        item
    end
  end

  def extract_header(header_node)
    return {
      :title => header_node.options[:raw_text].strip,
      :type => ITEM_TYPE_HEADER
    }
  end
end