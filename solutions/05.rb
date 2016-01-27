require 'digest/sha1'

class RepoObject < Struct.new(:name, :object)
end

class Proxy < BasicObject
  attr_reader :message, :result

  def initialize(message, success, receiver, result = nil)
    @message, @success, @receiver, @result = message, success, receiver, result
  end

  def success?
    @success
  end

  def error?
    not success?
  end

  def method_missing(name, *args, &block)
    @receiver.send(name, *args)
  end

  def respond_to_missing?(symbol, include_private)
    [:head, :get, :add, :remove, :commit, :checkout, :log].insances_methods
  end
end

class BranchProxy < BasicObject
  def initialize(receiving_repo, receiving_branch)
    @receiving_repo, @receiving_branch = receiving_repo, receiving_branch
  end

  def method_missing(name, *args, &block)
    if name == :checkout || name == :remove
      @receiving_branch.send(name, *args)
    else
      @receiving_repo.send(name, *args)
    end
  end

  def respond_to_missing?(symbol, include_private)
    [:create, :checkout, :remove, :list].include? symbol
  end
end

class Commit
  attr_accessor :message, :date, :objects

  def initialize(message, objects)
    @message = message
    @date = Time.new
    @objects = objects.dup
  end

  def hash
    Digest::SHA1.hexdigest "#{@date}#{@message}"
  end
end

class Branch
  attr_reader :name, :commits

  def initialize(name, commits, parent_repo)
    @name, @commits, @parent_repo = name, commits.dup, parent_repo
    @change_count, @head = 0, @commits.last
    if @head == nil
      @stage = []
    else
      @stage = @head.objects
    end
  end

  def head
    message = "Branch #{@name} does not have any commits yet."
    result = false
    if @head
      message = @head.message
      result = true
    end
    Proxy.new(message, result, self, @head)
  end

  def get(name)
    if @head == nil
      message, result = "Object #{name} is not committed.", false
      return Proxy.new(message, result, self)
    end

    wanted_object = @head.objects.detect{|object| object.name == name}
    if wanted_object
      message, result = "Found object #{name}.", true
      Proxy.new(message, result, self, wanted_object.object)
    else
      message, result = "Object #{name} is not committed.", false
      Proxy.new(message, result, self)
    end
  end

  def add(name, object)
    @change_count += 1
    object_index = index_of_object(name)
    if object_index != nil
      @stage[object_index] = RepoObject.new(name, object)
    else
      @stage.push RepoObject.new(name, object)
    end
    Proxy.new("Added #{name} to stage.", true, @parent_repo, object)
  end

  def remove(branch_name)
    @parent_repo.remove_branch(branch_name)
  end

  def remove_object(name)
    result = @stage.delete_at(index_of_object(name) || @stage.size)
    if result
      @change_count += 1
      message = "Added #{name} for removal."
    else
      message = "Object #{name} is not committed."
    end
    Proxy.new(message, !!result, @parent_repo, result)
  end

  def commit(commit_message)
    success = false
    if @change_count > 0
      message, = "#{commit_message}\n\t#{@change_count} objects changed"
      success  = true
      @head = Commit.new(commit_message, @stage)
      @commits.push @head
      @stage, @change_count = @head.objects.dup, 0
    else
      message = "Nothing to commit, working directory clean."
    end
    Proxy.new(message, success, @parent_repo)
  end

  def checkout(branch)
    @parent_repo.checkout_branch(branch)
  end

  def checkout_commit(commit_hash)
    target_commit = @commits.detect {|commit| commit.hash == commit_hash}
    message = "Commit #{commit_hash} does not exist."
    if target_commit
      @head = target_commit
      message = "HEAD is now at #{commit_hash}."
      @stage = @head.objects.dup
    end
    Proxy.new(message, !!target_commit, @parent_repo, target_commit)
  end

  private
  def index_of_object(name)
    @stage.find_index {|object| object.name == name}
  end
end

class ObjectStore
  def ObjectStore.init(&block)
    if block
      ObjectStore.new.instance_eval(&block)
    else
      ObjectStore.new
    end
  end

  def initialize
    @current_branch = Branch.new("master", [], self)
    @branches = [@current_branch]
  end

  def create(branch_name)
    message, result = "Branch #{branch_name} already exists.", false
    if not branch_index(branch_name)
      message, result = "Created branch #{branch_name}.", true
      @branches.push Branch.new(branch_name, @current_branch.commits, self)
    end
    Proxy.new(message, result, self)
  end

  def checkout(commit_hash)
    @current_branch.checkout_commit(commit_hash)
  end

  def remove(object_name)
    @current_branch.remove_object(object_name)
  end

  def checkout_branch(branch_name)
    target_branch = @branches.at(branch_index(branch_name) || @branches.size)
    message, result = "Branch #{branch_name} does not exist.", false
    if target_branch
      message, result = "Switched to branch #{branch_name}.", true
      @current_branch = target_branch
    end
    Proxy.new(message, result, self)
  end

  def remove_branch(branch_name)
    target_branch = @branches.at(branch_index(branch_name) || @branches.size)
    message, success = "Branch #{branch_name} does not exist.", false
    if target_branch != nil && target_branch.name != @current_branch.name
      message, success = "Removed branch #{branch_name}.", true
      @branches.delete_at branch_index(branch_name)
    elsif target_branch != nil
      message, success = "Cannot remove current branch.", false
    end
    Proxy.new(message, success, self)
  end

  def list
    message = @branches.map(&:name).sort.map {|name| "  " + name + "\n"}.join
    pattern = "  " + @current_branch.name
    message[pattern] = "* " + message[pattern].strip
    Proxy.new(message, true, self)
  end

  def branch
    BranchProxy.new(self, @current_branch)
  end

  def log
    if @current_branch.commits.empty?
      message = "Branch #{@current_branch.name} does not have any commits yet."
      Proxy.new(message, false, @current_branch)
    else
      format = "Commit %{hash}\nDate: %{date}\n\n\t%{message}"
      message = @current_branch.commits.reverse.map do |commit|
        date = commit.date.strftime("%a %b %d %H:%M %Y %z")
        format % {hash: commit.hash, date: date, message: commit.message}
      end
      Proxy.new(message.join("\n\n"), true, @current_branch)
    end
  end

  def method_missing(name, *args, &block)
    @current_branch.send(name, *args)
  end

  def respond_to_missing?(symbol, include_private)
    [:name, :head, :get, :add, :commit].include? symbol
  end

  private

  def branch_index(name)
    @branches.find_index {|branch| branch.name == name}
  end
end
