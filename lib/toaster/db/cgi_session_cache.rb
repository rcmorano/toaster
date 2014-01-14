

#
# Author: Waldemar Hummer (hummer@dsg.tuwien.ac.at)
#

require "toaster/db/cache"
require "toaster/markup/markup_util"

module Toaster
  class CGISessionCache < Cache

    KEY_CACHE = "__cache__"
    KEY_CACHE_SIZE = "__cachesize__"
    KEY_QUERY_KEYS = "__keys__"

    DO_CACHE_OBJECTS = false
    DO_CACHE_QUERIES = true

    def initialize(cgi_session)
      @session = cgi_session
      @cache = nil
      @hits = []
      @misses = []
      @dirty = false
    end

    def by_db_type(db_type)
      load_cache()

      return by_obj_prop("db_type", db_type)
    end

    def by_id(id)
      load_cache()

      return by_obj_props({"id" => id})
    end

    def by_obj_props(props_hash)
      load_cache()

      if DO_CACHE_QUERIES
        props_str = props_hash.inspect
        cached = @cache[KEY_QUERIES][props_str]
        if cached
          @hits << props_hash
          return cached
        end
      end

      if DO_CACHE_OBJECTS
        @cache[KEY_OBJECTS] = [] if !@cache[KEY_OBJECTS]
        puts "size: #{@cache[KEY_OBJECTS].size}"
        objs = @cache[KEY_OBJECTS]
        result = []
        objs.each do |o|
          arr = o.kind_of?(Array) ? o : [o]
          all_match = true
          arr.each do |item|
            if !item || !matches(item, props_hash)
              all_match = false
              break
            end
          end
          result << o if all_match
        end
        if result.size == 0
          @misses << props_hash
          return nil 
        end
        @hits << props_hash
        return result
      end

      @misses << props_hash
      return nil
    end

    def by_key(key_path_array)
      load_cache()

      if DO_CACHE_QUERIES
        key_path_str = key_path_array.inspect
        cached = @cache[KEY_QUERIES][key_path_str]
        if cached
          @hits << key_path_array
          return cached
        end
      end

      if DO_CACHE_OBJECTS
        key_path_array = [key_path_array] if !key_path_array.kind_of?(Array)
        obj = @cache
        key_path_array.each do |k|
          obj = obj[k]
          if !obj
            @misses << key_path_array
            return nil
          end
        end
        @hits << key_path_array
        #@cache[KEY_QUERIES][key_path_str] = obj
        return obj
      end

      @misses << key_path_array
      return nil
    end

    def set(value, key=KEY_OBJECTS)
      load_cache()

      if key.kind_of?(Array) && key[0] == KEY_QUERIES
        #puts "setting cache value: #{value}"
        @cache[KEY_QUERIES][key[1]] = value
        @dirty = true
        return
      end

      if DO_CACHE_OBJECTS
        i = next_index(key)
        obj_key = "#{KEY_CACHE}.#{key}.#{i}"
        #key = "#{KEY_CACHE}.#{key}"
        #puts "setting '#{obj_key}'"
        value = value[0] if value.kind_of?(Array) && value.size == 1
        @session[obj_key] = value

        @cache[key] = [] if !@cache[key]
        value = [value] if !value.kind_of?(Array)
        @cache[key].concat(value)
        #@cache[key] = @cache[key][0] if @cache[key].size == 1
        @dirty = true
      end

    end

    def clear()
      @cache = nil
      @session[KEY_CACHE] = "{}"
      @session.update()
      load_cache()
    end

    def get_hits()
      @hits
    end

    def get_misses()
      @misses
    end

    def flush()
      return if !@dirty
      @session[KEY_CACHE] = MarkupUtil.to_json(@cache)
      @session.update()
    end

    private

    def load_cache()
      return @cache if @cache

      begin
        @cache = @session[KEY_CACHE] ? MarkupUtil.parse_json(@session[KEY_CACHE]) : {}
      rescue => ex
        puts "Unable to parse session cache JSON: #{ex}"
        @session[KEY_CACHE] = "{}"
        @cache = @session[KEY_CACHE] ? MarkupUtil.parse_json(@session[KEY_CACHE]) : {}
      end

      @cache = {} if !@cache
      @cache[KEY_QUERIES] = {} if !@cache[KEY_QUERIES]
      @cache[KEY_OBJECTS] = [] if !@cache[KEY_OBJECTS]

    end

    def next_index(key=KEY_OBJECTS)
      key = "#{KEY_CACHE_SIZE}.#{key}"
      @session[key] = "0" if !@session[key]
      i = @session[key].to_i + 1
      @session[key] = i.to_s
      return i - 1 # subtract 1 from cache size for 0-based cache index
    end

    def by_obj_prop(prop, value)
      return by_obj_props({prop => value})
    end

    def matches(obj, props)
      props.each do |prop,value|
        if !obj.kind_of?(Hash)
          puts "WARN: Expected object of type Hash but got object of type #{obj.class}"
          #puts "#{obj} "
        end
        value1 = obj[prop]
        if value1 != value
          return false
        end
      end
      return true
    end

  end
end
