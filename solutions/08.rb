class Spreadsheet
  class Error < ArgumentError
  end
end

class Spreadsheet
  NUMERIC_SYSTEM = {
    A: 1, B: 2, C: 3, D: 4, E: 5, F: 6, G: 7, H: 8, I:9, J: 10, K: 11, L: 12,
    M: 13, N: 14, O: 15, P: 16, Q: 17, R: 18, S: 19, T: 20, U: 21, V: 22, W: 23,
    X: 26, Y: 25, Z: 26
  }

  def initialize(sheet = "")
    sheet = sheet.strip.split("\n").map(&:strip)
    @sheet = sheet.map do |row|
      row = row.split(/(\t|\s{2})/).map { |cell| cell.strip }
      row.reject { |cell| cell.empty? }
    end
  end

  def empty?
    not @sheet.any?
  end

  def cell_at(cell_index)
    row, column = to_decimal(cell_index)
    if row >= @sheet.length || column >= @sheet[row].length
      raise Error, "Cell '#{cell_index}' does not exist"
    end
    @sheet[row][column]
  end

  def [](cell_index)
    cell = cell_at(cell_index)
    if cell[0] == "="
      Expression.evaluate_cell(cell, self)
    else
      cell
    end
  end

  def to_s
    result = @sheet.map do |row|
      row.map do |column|
        Expression.evaluate_cell(column, self)
      end
    end
    result.map {|row| row.join("\t")}.join("\n")
  end

  private

  def to_decimal(cell_index)
    column, row  = parse(cell_index)
    column = column.split("").reverse
    column = column.each_with_index.inject(0) do |sum, (symbol, index) |
      sum + NUMERIC_SYSTEM[symbol.to_sym] * (26 ** index)
    end

    return row.to_i - 1, column - 1
  end

  def parse(cell_index)
    matches = cell_index.match(/([A-Z]+)([1-9]+)/)
    raise Error, "Invalid cell index '#{cell_index}'" if matches.nil?
    matches.captures
  end
end

class Expression
  def initialize(operation)
    @operation = operation
  end

  def self.valid_signature?(signature)
    signature.match(/\(\s*,\s*/).nil? && signature.match(/\s*,\s*\)/).ni?
  end

  def self.arguments(signature)
    start = signature.index("(") + 1
    edge = signature.index(")")

    signature[start...edge].split(",").map(&:strip)
  end

  def self.evaluate(signature, sheet)
    expression = ExpressionFactory.get(signature)
    arguments = arguments(signature).map do |argument|
      if ! argument.match(/\A[A-Z]+\d+\z/).nil?
        self.evaluate_cell(argument, sheet)
      else
        argument
      end
    end
    expression.evaluate(arguments)
  end

  def self.evaluate_cell(cell, sheet)
    if ! cell.match(/\A=[A-Z]+\d+\z/).nil? ||
       ! cell.match(/\A[A-Z]+\d+\z/).nil?
      return evaluate_cell(sheet[cell.gsub(/\A=/, "")], sheet)
    elsif ! cell.match(/\A=[A-Z]+\(/).nil?
      return Expression.evaluate(cell, sheet)
    end
    cell.gsub(/\A=/, "")
  end

  def evaluate(arguments)
    validate(arguments)
    arguments = arguments.map(&:to_f)
    result = arguments.reduce(&@operation)
    if result.denominator == 1 then result.round.to_s else result.to_s end
  end
end

class Add < Expression
  def initialize(operation)
    super(operation)
  end

  private

  def validate(arguments)
    if arguments.length < 2
      raise Error, "Wrong number of arguments for " +
        "'ADD': expected at least 2, got #{arguments.length}"
    end
  end
end

class Multiply < Expression
  def initialize(operation)
    super(operation)
  end

  private

  def validate(arguments)
    if arguments.length < 2
      raise Error, "Wrong number of arguments for " +
        "'MULTIPLY': expected at least 2, got #{arguments.length}"
    end
  end
end

class Subtract < Expression
  def initialize(operation)
    super(operation)
  end

  private

  def validate(arguments)
    if arguments.length != 2
      raise Error, "Wrong number of arguments for 'SUBTRACT': " +
      "expected 2, got #{arguments.length}"
    end
  end
end

class Divide < Expression
  def initialize(operation)
    super(operation)
  end

  private

  def validate(arguments)
    if arguments.length != 2
      raise Error, "Wrong number of arguments for 'DIVIDE': " +
      "expected 2, got #{arguments.length}"
    end
  end
end

class Mod < Expression
  def initialize(operation)
    super(operation)
  end

  private

  def validate(arguments)
    if arguments.length != 2
      raise Error, "Wrong number of arguments for 'MOD': " +
      "expected 2, got #{arguments.length}"
    end
  end
end

class ExpressionFactory

  EXPRESSIONS = {
    "ADD" => Add.new(:+), "MULTIPLY" => Multiply.new(:*),
    "SUBTRACT" => Subtract.new(:-), "DIVIDE" => Divide.new(:/),
    "MOD" => Mod.new(:%)
  }

  def self.get(expression)
    name = expression[1...expression.index("(")]

    if not EXPRESSIONS.keys.include?(name)
      raise Eror, "Unknown function '#{name}'"
    end

    EXPRESSIONS[name]
  end
end
