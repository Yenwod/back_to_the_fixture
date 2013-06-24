# Extension to make it easy to read and write data to a file.

class BackToTheFixture

  # reference models with plural name
  def self.load_tree(files, opts = {})

    raise "you must supply a file parameter" if files.nil?
    files = Array.wrap(files)
    files.each do |file|
      if File.directory?(file)
        file = Dir[file  +  '*.yml*']
      end
      Array.wrap(file).each do |f|
      records_hash = read_yaml_file(Rails.root + f, true)
      records_hash.each do |class_name, records|

        klass = class_name.to_s.classify.constantize
        klass_sym = class_name.underscore.downcase.pluralize.to_sym
        if opts[:except_models].present?
          next if opts[:except_models].include?(klass_sym)
        end
        if opts[:reset_sequence]
          reset_mysql_sequence = "ALTER TABLE #{klass.table_name} AUTO_INCREMENT = 1;"
          ActiveRecord::Base.connection.execute(reset_mysql_sequence);
          if connection.respond_to?(:reset_pk_sequence!)
            connection.reset_pk_sequence!(klass.table_name)
          end
        end
        except = (opts[:except_attributes][klass_sym] || []) | (opts[:except_attributes][:global] || []) if opts[:except_attributes].present?
        klass.destroy_all if opts[:destroy_all].present?
        records.each do |record|
          r = record.with_indifferent_access.except(*except) if opts[:except_attributes].present?
          klass.create(r || record, :without_protection => true)
        end
      end
      end
    end
    true
  end

  def self.dump_tree(opts)
    raise "you must pass a :template hash object or path to yaml" unless opts[:template]
    if opts[:template].is_a?(String)
      opts[:template] = read_yaml_file(opts[:template])
    end
    if opts[:split]
      opts[:save_path] ||= 'fixtures/models/' + opts[:template_key].to_s.downcase
    else
      opts[:save_path] += 'fixtures/trees/' 
      opts[:save_name] ||= opts[:template_key].to_s.downcase + "_tree.yml"
      save_as = Rails.root + opts[:save_path] + opts[:save_name]
      FileUtils.touch(save_as) unless File.exists? save_as
    end
    FileUtils.mkdir_p(opts[:save_path]) unless File.exists? opts[:save_path]
    @records = Hash.new()
    results = opts[:template][opts[:template_key]]
    parse_template(nil, results)
    if opts[:merge]
      old_tree = read_yaml_file(save_as) || {}
      keys = @records.keys | old_tree.keys
      keys.each {|k| @records[k] = @records[k] | Array.wrap(old_tree[k])}
    end
    if opts[:split]
      @records.each do |k,v|
        file = Rails.root + opts[:save_path] + "#{k.to_s.downcase}.yml"
        v = merge_fixtures(file, {k => v}) if opts[:merge]
        write_yaml_file(file, {k => v}, opts[:append])
      end
    else
      write_yaml_file(save_as, @records, opts[:append])
    end
    return true
  end

    protected

    def merge_fixtures(file, records)
      old_tree = read_yaml_file(file) || nil
      keys = records.keys | old_tree.keys
      keys.each {|k| records[k] = records[k] | Array.wrap(old_tree[k])}
      return records
    end

    def self.read_yaml_file(file, parse = nil, pattern = '<%% %%>')
      raw_data = File.read(File.expand_path(file, Rails.root))
      data = Erubis::Eruby.new(raw_data, :pattern => pattern).result if parse
      YAML::load(data || raw_data)
    end

    # append won't work on trees; will need to use merge for those
    def self.write_yaml_file(file, records, append = nil)
      write_method = append ? 'a' : 'w'
      File.open(file, write_method) do  |f|
        yaml = records.to_yaml(:SortKeys => true)
        if append
          yaml = records.values.first.to_yaml(:SortKeys => true) if records.is_a?(Hash)
          yaml = yaml.lines.map{|line| line unless line == "---\n"}.join
        end
        f.write yaml
      end
    end

    def self.parse_branch(results, hash_template = {})
      result_array = Array.new
      if results.respond_to?(:each)
        results = results.scoped
        results = results.send('where', hash_template[:where]) if hash_template[:where].present? 
        results = results.send('order', hash_template[:order]) if hash_template[:order].present? 
        results = results.send('limit', hash_template[:query_limit]) if hash_template[:query_limit].present? 
        if hash_template[:limit_by].present?
          hash =  results.group_by(&hash_template[:limit_by].keys.first)
          hash.each {|k,v| hash[k] = v.take(hash_template[:limit_by].values.first)}
          results = hash.values.flatten
        end
        results = results.send('take', hash_template[:hard_limit]) if hash_template[:hard_limit].present? 
        result_class = results.first.class.to_s
      else
        result_class = results.class.to_s
      end

      Array.wrap(results).each do |result|
        parse_template(result, hash_template[:grab])
        h_result = result.attributes
        if hash_template[:sanitize]
          hash_template[:sanitize].each_pair {|k,v| hash_template[:sanitize][k] = Erubis::Eruby.new(v, :pattern => '<%%% %%%>').result}
          h_result = h_result.with_indifferent_access.merge!(hash_template[:sanitize]) 
        end
        result_array.push h_result.to_hash
      end
      if result_array.empty?
          # do nothing
        elsif @records[result_class].nil?
          @records[result_class] = result_array
        else
          @records[result_class].concat result_array
        end
      return results
    end

    def self.parse_template(record, items)
      items = Array.wrap(items)
      items.each do |item|
        
        if item.class == Symbol # like :events
          hash_template = {}
          if record.nil?
            results = item.to_s.classify.constantize.scoped
          else
            results = record.send(item)
          end
        else # else it's a hash, like {:user => [:posts]}; single k/v 

          hash_template = item[item.keys.first]
          if record.nil?
            results = item.keys.first.to_s.classify.constantize.scoped
          else
            results = record.send(item.keys.first)
          end
        end
        parse_branch(results, hash_template)
      end
    end




end #class

class ActiveRecord::Base

  class << self

    # Writes content of this table to db/table_name.yml, or the specified file.
    #
    # Writes all content by default, but can be limited.
    def dump_to_file(path=nil, limit=nil, opts={})
      opts[:limit] = limit if limit
      path ||= "db/#{table_name}.yml"
      write_file(File.expand_path(path, Rails.root), self.find(:all, opts).to_yaml)
      habtm_to_file
    end

    # dump the habtm association table
    def habtm_to_file
      path ||= "db/#{table_name}.yml"
      joins = self.reflect_on_all_associations.select { |j|
        j.macro == :has_and_belongs_to_many
      }
      joins.each do |join|
        hsh = {}
        connection.select_all("SELECT * FROM #{join.options[:join_table]}").each_with_index { |record, i|
          hsh["join_#{'%05i' % i}"] = record
        }
        write_file(File.expand_path("db/#{join.options[:join_table]}.yml", Rails.root), hsh.to_yaml(:SortKeys => true))
      end
    end

    def load_from_file(path=nil)
      path ||= "fixtures/models/#{table_name}.yml"
      self.destroy_all
      reset_mysql_sequence = "ALTER TABLE #{self.table_name} AUTO_INCREMENT = 1;"
      ActiveRecord::Base.connection.execute(reset_mysql_sequence);

      raw_data = File.read(File.expand_path(path, Rails.root))
      erb_data = Erubis::Eruby.new(raw_data, :pattern => '<%% %%>').result
      records = YAML::load( erb_data )
      records.each do |name, record|
        unless 'test' == Rails.env
          puts "______________"
          puts record.to_yaml
          puts "______________"
        end
        
        record_copy = self.new(record,  :without_protection => true)

        # For Single Table Inheritance
        klass_col = self.inheritance_column
        if record[klass_col]
          record_copy.type = record[klass_col]
        end

        record_copy.save(:validate => false)
      end

      if connection.respond_to?(:reset_pk_sequence!)
        connection.reset_pk_sequence!(table_name)
      end
      true
    end


    # Write a file that can be loaded with +fixture :some_table+ in tests.
    # Uses existing data in the database.
    #
    # Will be written to +test/fixtures/table_name.yml+. Can be restricted to some number of rows.
    # 

    # See tasks/ar_fixtures.rake for what can be done from the command-line, or use "rake -T" and look for items in the "db" namespace.

    def to_fixture(opts={})
      opts[:save_path] ||= "fixtures/models"
      opts[:save_name] ||= "#{table_name}.yml"
      write_method = opts[:append] ? 'a' : 'w'
      internal_opts = [:save_path, :save_name, :append]
      File.open(Rails.root + opts[:save_path] + opts[:save_name], write_method) do  |file|
        yaml = self.scoped.where(opts.except(*internal_opts)).inject({}) do |hsh, record|
          hsh.merge((record.attributes[opts[:key].to_s] || "#{self}-#{'%05i' % record.id rescue record.id}") => record.attributes)
        end.to_yaml(:SortKeys => true)
        if opts[:append]
          yaml = yaml.lines.map{|line| line unless line == "---\n"}.join
        end
        file.write yaml
      end
        #habtm_to_fixture
        return true
    end

    # Write the habtm association table
    def habtm_to_fixture(opts={save_path: "spec/fixtures/"})
      internal_opts = [:save_as]
      joins = self.reflect_on_all_associations.select { |j|
        j.macro == :has_and_belongs_to_many
      }
      joins.each do |join|
        hsh = {}
        connection.select_all("SELECT * FROM #{join.options[:join_table]}").each_with_index { |record, i|
          hsh["join_#{'%05i' % i}"] = record
        }
        write_file(File.expand_path(opts[:path] + "#{join.options[:join_table]}.yml", Rails.root), hsh.to_yaml(:SortKeys => true))
      end
    end

    # Generates a basic fixture file in test/fixtures that lists the table's field names.
    #
    # You can use it as a starting point for your own fixtures.
    #
    #  record_1:
    #    name:
    #    rating:
    #  record_2:
    #    name:
    #    rating:
    #
    # TODO Automatically add :id field if there is one.
    def to_skeleton(opts={save_path: "spec/fixtures/"})
      record = {
        "record_1" => self.new.attributes,
        "record_2" => self.new.attributes
      }
      write_file(File.expand_path(opts[:path] + "#{table_name}.yml", Rails.root),
      record.to_yaml)
    end

    def write_file(path, content) # :nodoc:
      f = File.new(path, "w+")
      f.puts content
      f.close
    end

  
  end
end
