require 'kramdown'
require 'pygments'
require 'uri'

module Jekyll
  module Converters
    class Markdown
      class CustomKramdownParser
        def initialize(config)
          @config = config
        end

        def convert(content)
          options = Utils.symbolize_hash_keys(@config['kramdown'])
          options[:baseurl] = @config['baseurl']
          Kramdown::Document.new(content, options).to_upsrc
        end
      end
    end
  end
end

module Kramdown
  module Converter
    class Upsrc < Html

      def convert_header(el, indent)
        attr = el.attr.dup
        el_id = generate_id(el.options[:raw_text])

        if @options[:auto_ids] && !attr['id']
          attr['id'] = el_id
        end
        @toc << [el.options[:level], el_id, el.children] if el_id && in_toc?(el)
        level = output_header_level(el.options[:level])

        if level <= 3
          anchor = Element.new(:a, nil, {'href' => '#' + el_id, 'class' => 'anchor-link'})
          el.children.push(anchor)
        end

        anchor = format_as_block_html("a", {'name' => el_id, 'class' => 'elem-anchor'}, inner(Element.new(:a, nil), indent), indent)
        header = format_as_block_html("h#{level}", attr, inner(el, indent), indent)
        anchor + header
      end

      # Convert a <code> block
      # Overrides Html#convert_codeblock to support highlighting lines in the class
      # attribute (class="csharp{1-3}") and to change the generated elements and attributes
      # to use expected webhelp values
      def convert_codeblock(el, indent)
        attr = el.attr.dup
        lang = self.extract_code_language(attr) || 'text'
        highlight_lines = ''

        if attr['class'] and attr['class'].scan(/\{[\d\-\,]+\}/).length > 0
          lang_parts = attr['class'].split('{')
          highlight_lines = "{#{lang_parts[1]}"
        end

        code = highlight_code(el.value, lang, :block, { :highlight_lines => highlight_lines })
        code_attr = {}
        code_attr['class'] = "code-block__wrapper"
        code_attr['class'] += " code-block _highlighted lang_#{lang}" if lang

        format_as_block_html('pre', {}, format_as_span_html('code', code_attr, code), 0)
      end

      # Extract the code block/span language from the class attribute, if specified.
      # Skip any {} chars (used for highlighting lines)
      def extract_code_language(attr)
        if attr['class']
          class_attr = attr['class']

          if class_attr.scan(/\{|\}/).length > 0
            class_attr = class_attr.split('{')[0]
          end

          class_attr.scan(/\blanguage-(\w+)\b/).first.first
        end
      end

      # Convert a code span element
      # Overrides Html#convert_codespan to provide different class attributes, as the default
      # implementation only provides 'highlighter-pygments'
      def convert_codespan(el, indent)
        attr = el.attr.dup
        lang = extract_code_language!(attr) || 'text'
        result = highlight_code(el.value, lang, :span)
        attr['class'] = 'code'
        attr['class'] += " highlight language-#{lang}" if lang
        format_as_span_html('code', attr, result)
      end

      # Override Html#convert_a to identify external links. Also converts .md links to .html
      def convert_a(el, indent)
        res = inner(el, indent)
        attr = el.attr.dup
        attr['href'] = '' if attr['href'].nil?
        href = attr['href']
        is_external = href.start_with?('http://', 'https://', 'ftp://', '//')
        attr['data-bypass'] = 'yes' if is_external
        if href.start_with?('mailto:')
          mail_addr = href[7..-1]
          attr['href'] = obfuscate('mailto') << ":" << obfuscate(mail_addr)
          res = obfuscate(res) if res == mail_addr
        end

        href = @options[:baseurl] + href[1, href.length - 1] if href.start_with?('/') and !href.start_with?('//')
        uri = URI(href)
        uri.path = uri.path.chomp(File.extname(uri.path)) + '.html' if File.extname(uri.path) == '.md' and !is_external
        attr['href'] = uri.to_s

        format_as_span_html(el.type, attr, "<span>#{res}</span>")
      end

      def convert_blockquote(el, indent)

        if el.children[0].type == :p and el.children[0].children[0].type == :strong
          p = el.children[0]
          type = inner_text(p.children[0], []).downcase
          type = type + ' ' + el.attr['class'] unless el.attr['class'].nil?
          el.attr['class'] = type

          p.children.slice!(0)
        end

        format_as_indented_block_html('aside', el.attr, inner(el, indent), indent)
      end

      def inner_text(el, stack)
        result = ''
        stack.push el
        result << el.value unless el.value.nil?
        el.children.each do |inner_el|
          result << inner_text(inner_el, stack)
        end
        stack.pop
        result
      end
    end

    module SyntaxHighlighter
      module Pygments
        ::Kramdown::Converter.add_syntax_highlighter(:pygments, Pygments)

        def self.call(converter, text, lang, type, code_opts)
          # TODO: Merge this with :options below
          opts = converter.options[:syntax_highlighter_opts].dup

          hl_lines = ''
          highlight_lines = code_opts[:highlight_lines] || ''
          if highlight_lines
            hl_lines = highlight_lines.gsub(/[{}]/, '').split(',').map do |ln|
              if matches = /(\d+)-(\d+)/.match(ln)
                ln = Range.new(matches[1], matches[2]).to_a.join(' ')
              end
              ln
            end.join(' ')
          end

          if lang
            ::Pygments.highlight(text,
                               :lexer => lang || 'text',
                               :options => {
                                 :encoding => 'utf-8',
                                 :nowrap => true,
                                 :hl_lines => hl_lines
                               })
          else
            escape_html(text)
          end
        end
      end
    end
  end

  module Parser
    class GFM2 < GFM
      def parse
        super
      end

      FENCED_CODEBLOCK_MATCH = /^(([~`]){3,})\s*?(\w+[\{\}\,\d\-]*?)?\s*?\n(.*?)^\1\2*\s*?\n/m
    end
  end
end
