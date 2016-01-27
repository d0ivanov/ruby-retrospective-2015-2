module LazyMode
  def self.create_file(file_name, &block)
    file_context = FileContext.new(file_name)
    file_context.instance_eval(&block)
    file_context.subject
  end


  class File
    attr_accessor :name

    def initialize(name, note_descriptions)
      @name, @note_descriptions = name, note_descriptions
    end

    def notes
      @note_descriptions.map {|description| description.note}
    end

    def daily_agenda(date)
      notes = @note_descriptions.map do |description|
        description.note_for(date)
      end
      Agenda.new(notes.compact)
    end

    def weekly_agenda(date)
      notes = []
      7.times do
        notes.push(*daily_agenda(date).notes)
        date = date.add(1)
      end
      Agenda.new(notes)
    end
  end

  class Agenda
    attr_reader :notes

    def initialize(notes)
      @notes = notes
    end

    def where(tag: nil, text: nil, status: nil)
      by_tag = filter_by_tag(@notes, tag)
      by_text = filter_by_text(@notes, text)
      by_status = filter_by_status(@notes, status)

      notes = by_tag & by_text & by_status
      Agenda.new(notes)
    end

    private

    def filter_by_tag(notes, tag)
      return notes if tag == nil
      notes.select {|note| note.tags.include? tag}
    end

    def filter_by_text(notes, text)
      return notes if text == nil
      notes.select do |note|
        text.match(note.header) != nil || text.match(note.body) != nil
      end
    end

    def filter_by_status(notes, status)
      return notes if status == nil
      notes.select {|note| note.status == status}
    end
  end

  class Note
    attr_accessor :header, :tags, :file_name, :status, :body, :date

    def initialize(header, tags, file_name)
      @header, @tags, @file_name = header, tags, file_name
      @status, @body = :topostpone, ""
    end
  end

  class FileContext
    def initialize(name)
      @name = name
      @note_descriptions = []
    end

    def note(header, *tags, &block)
      note_context = NoteContext.new(header, @name, tags)
      note_context.instance_eval(&block)
      @note_descriptions.push(*note_context.subject)
    end

    def subject
      File.new(@name, @note_descriptions)
    end
  end

  class NoteContext
    def initialize(header, file, tags)
      @file = file
      @note = Note.new(header, tags, file)
      @note_description = NoteDescription.new(@note)
      @notes = []
    end

    def note(header, *tags, &block)
      note_context = NoteContext.new(header, @file, tags)
      note_context.instance_eval(&block)
      @notes.push(*note_context.subject)
    end

    def scheduled(schedule)
      repeats = schedule(schedule)
      @note.date = Date.new(repeats.first)
      @note_description.schedule = repeats[1]
    end

    def status(status)
      @note.status = status
    end

    def body(body)
      @note.body = body
    end

    def subject
      @notes.push @note_description
    end

    private

    def schedule(schedule)
      /(\d+-\d+-\d+)\s*(\+?(\d+)([m|d|w]))?/.match(schedule).captures
    end
  end

  class Date
    include Comparable

    DAYS = 30
    MONTHS = 12

    attr_reader :year, :month, :day

    def initialize(full_date)
      @year, @month, @day = full_date.split("-").map {|date| date.to_i}
    end

    def to_s
      year, month, day = @year.to_s, @month.to_s, @day.to_s
      "#{prefix(year, 4, "0")}-#{prefix(month, 2, "0")}-#{prefix(day, 2, "0")}"
    end

    def add(days)
      date = [calculate_year(days), calculate_month(days),
              calculate_day(days)]
      Date.new date.join("-")
    end

    def <=>(other)
      if @year != other.year
        return @year <=> other.year
      end
      if @month == other.month
        @day <=> other.day
      else
        @month <=> other.month
      end
    end

    private

    def prefix(string, count, prefix)
      (count - string.length).times do
        string = prefix + string
      end
      string
    end

    def calculate_day(days)
      new_day = ((@day + days) % DAYS)
      if new_day == 0
        new_day = 1
      else
        new_day
      end
    end

    def calculate_month(days)
      new_month = (@month + ((@day + days) / DAYS)) % MONTHS
      if new_month == 0
        new_month = 1
      else
        new_month
      end
    end

    def calculate_year(days)
      @year + ((@month + ((@day + days) / DAYS)) / MONTHS)
    end
  end

  class NoteDescription
    include Enumerable
    attr_accessor :note, :schedule

    def initialize(note)
      @note = note
    end

    def each
      loop do
        date = @note.date.add(step)
        note = @note.dup
        note.date = date
        yield note
      end
    end

    def note_for(date)
      return @note if @note.date == date
      return nil if @schedule == nil || @note.date > date
      lazy.take_while {|note| date >= note.date}.find{|note| note.date == date}
    end

    private

    def step
      days = if @schedule[2] == "w"
               7
             elsif @schedule[2] == "m"
               Date::DAYS
             else
               1
             end
      days * @schedule[1].to_i
    end
  end
end
