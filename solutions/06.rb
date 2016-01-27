module TurtleGraphics
  class Position < Struct.new(:x, :y)
  end

  class Orientation < Struct.new(:x, :y)
  end

  class Turtle
    ORIENTATION = { up: Orientation.new(0, -1), down: Orientation.new(0, 1),
      right: Orientation.new(1, 0), left: Orientation.new(-1, 0)
    }

    def initialize(x, y)
      @spawned, @plain = false, Canvas::Plain.new(x, y)
      @orientation, @position = ORIENTATION[:right], Position.new(0, 0)
    end

    def move
      spawn_at(@position.x, @position.y) if not @spawned
      x, y = @position.x + @orientation.x, @position.y + @orientation.y
      new_position = reposition(Position.new(x, y))
      spawn_at(new_position.x, new_position.y)
    end

    def turn_left
      @orientation = Orientation.new(@orientation.y, -1 * @orientation.x)
    end

    def turn_right
      @orientation = Orientation.new(-1 * @orientation.y, @orientation.x)
    end

    def spawn_at(x, y)
      @spawned = true
      @position = Position.new(x, y)
      @plain.visit(@position)
    end

    def look(orientation)
      @orientation = ORIENTATION[orientation]
    end

    def draw(canvas = nil, &block)
      instance_eval(&block) if block_given?
      if canvas != nil
        canvas.draw @plain
      else
        @plain.plain
      end
    end

    private

    def reposition(current_position)
      if @plain.outside_column?(current_position)
        Position.new(0, current_position.y)
      elsif @plain.outside_row?(current_position)
        Position.new(current_position.x, 0)
      else
        current_position
      end
    end
  end

  module Canvas
    class Plain
      def initialize(x, y)
        @rows, @columns = y, x
        @canvas = []
        y.times do |row|
          @canvas[row] = []
          x.times { |column| @canvas[row][column] = 0 }
        end
      end

      def visit(position)
        @canvas[position.y][position.x] += 1
      end

      def plain
        @canvas.map(&:clone).clone
      end

      def outside_column?(position)
        position.x >= @columns
      end

      def outside_row?(position)
        position.y >= @rows
      end
    end

    class ASCII
      def initialize(symbols)
        @delta = (1.to_f / (symbols.size - 1).to_f)
        @symbols = {}
        symbols.each_with_index do |symbol, index|
          @symbols[Range.new((index - 1) * @delta, index * @delta)] = symbol
        end
      end

      def draw(plain)
        drawing = plain.plain.each.map do |row|
          row.map do |value|
            representation(intensity(value, plain.plain))
          end
        end

        drawing.map(&:join).map {|str| str + "\n"}.join.strip
      end

      private

      def max_visits(plain)
        plain.map(&:max).max
      end

      def intensity(pixel, plain)
        pixel.to_f / (max_visits plain).to_f
      end

      def representation(intensity)
        @symbols.each do |range, value|
          return value if range.include? intensity
        end
      end
    end

    class HTML
      TEMPLATE = %{
        <!DOCTYPE html>
        <html>
        <head>
          <title>Turtle graphics</title>

          <style>
            table {
              border-spacing: 0;
            }

            tr {
              padding: 0;
            }

            td {
              width: %dpx;
              height: %dpx;

              background-color: black;
              padding: 0;
            }
          </style>
        </head>
        <body>
          <table>
            %s
          </table>
        </body>
        </html>
      }

      def initialize(cell_size)
        @cell_size = cell_size
      end

      def draw(plain)
        table = representation(plain).map do |row|
          "<tr>#{row.join}</tr>"
        end
        TEMPLATE % [@cell_size, @cell_size, table.join]
      end

      private

      def representation(plain)
        template = "<td style='opacity: %.2f'></td>"
        plain.plain.each.map do |row|
          row.map do |pixel|
            template % [intensity(pixel, plain.plain)]
          end
        end
      end

      def max_visits(plain)
        plain.map(&:max).max
      end

      def intensity(pixel, plain)
        pixel.to_f / (max_visits plain).to_f
      end
    end
  end
end
