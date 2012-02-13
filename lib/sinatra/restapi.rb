require 'json'
module Sinatra::RestAPI
  def self.registered(app)
    app.helpers Helpers
  end

  def rest_create(path, model, &blk)

    #delete
    delete path + '/:id' do
      @service_type = model.find(params[:id])
      @service_type.destroy
    end

    #post
    post path do
      params.merge! Yajl::Parser.parse(request.body.read.to_s)
      $stderr.puts params
      object = model.create(params);
      object.to_json
    end




    put path + '/:id' do
      params.merge! Yajl::Parser.parse(request.body.read.to_s)
      item = model.find(params['id'])
      if item.update_attributes(params)
        json item
      else
        throw :halt, [404,'Cannot update']
      end
    end

    #index
    get path do
      $stderr.puts params
      search_params = ""
      query = {}
      params.each do |k, v|
        if k != 'limit' and k != 'skip' and v.length > 0
          query[k.to_s] = /#{v}/i
        end
      end
      $stderr.puts query
      limit       = params['limit'].to_i || 10
      skip        = params['skip'].to_i  || 0
      short_title = params['title']

      total =  model.where(query).all.count
      items =  model.where(query).all.limit(limit).skip(skip)

      res  = {
        skip:  skip,
        total: total,
        limit: limit,
        items: items
      }
      json res
    end
  end


  # ### rest_get(path, &block) [method]
  # This is the same as `rest_resource`, but only handles *GET* requests.
  #
  def rest_get(path, options={}, &blk)
    get path do |*args|
      @object = yield(*args) or pass
      rest_respond @object
    end
  end

  # ### rest_edit(path, &block) [method]
  # This is the same as `rest_resource`, but only handles *PUT*/*POST* (edit)
  # requests.
  #
  def rest_edit(path, options={}, &blk)
    callback = Proc.new { |*args|
      @object = yield(*args) or pass
      rest_params.each { |k, v| @object.send :"#{k}=", v  unless k == 'id' }

      return 400, @object.errors.to_json  unless @object.valid?

      @object.save
      rest_respond @object
    }

    # Make it work with `Backbone.emulateHTTP` on.
    put  path, &callback
    post path, &callback
  end

  # ### rest_delete(path, &block) [method]
  # This is the same as `rest_resource`, but only handles *DELETE* (edit)
  # requests. This uses `Model#destroy` on your model.
  #
  def rest_delete(path, options={}, &blk)
    delete path do |*args|
      @object = yield(*args) or pass
      @object.destroy
      rest_respond :result => :success
    end
  end

  # ### JSON conversion
  #
  # The *create* and *get* routes all need to return objects as JSON. RestAPI
  # attempts to convert your model instances to JSON by first trying
  # `object.to_json` on it, then trying `object.to_hash.to_json`.
  #
  # You will need to implement `#to_hash` or `#to_json` in your models.
  #
  #     class Album < Sequel::Model
  #       def to_hash
  #         { :id     => id,
  #           :title  => title,
  #           :artist => artist,
  #           :year   => year }
  #       end
  #     end

  # ### Helper methods
  # There are some helper methods that are used internally be `RestAPI`,
  # but you can use them too if you need them.
  #
  module Helpers
    # #### rest_respond(object)
    # Responds with a request with the given `object`.
    #
    # This will convert that object to either JSON or XML as needed, depending
    # on the client's preferred type (dictated by the HTTP *Accepts* header).
    #
    def rest_respond(obj)
      case request.preferred_type('*/json', '*/xml')
      when '*/json'
        content_type :json
        rest_convert_to_json obj

      else
        pass
      end
    end

    # #### rest_params
    # Returns the object from the request.
    #
    # If the client sent `application/json` (or `text/json`) as the content
    # type, it tries to parse the request body as JSON.
    #
    # If the client sent a standard URL-encoded POST with a `model` key
    # (happens when Backbone uses `Backbone.emulateJSON = true`), it tries
    # to parse its value as JSON.
    #
    # Otherwise, the params will be returned as is.
    #
    def rest_params
      if File.fnmatch('*/json', request.content_type)
        JSON.parse request.body.read

      elsif params['model']
        # Account for Backbone.emulateJSON.
        JSON.parse params['model']

      else
        params
      end
    end

    def rest_convert_to_json(obj)
      # Convert to JSON. This will almost always work as the JSON lib adds
      # #to_json to everything.
      json = obj.to_json

      # The default to_json of objects is to JSONify the #to_s of an object,
      # which defaults to #inspect. We don't want that.
      return json  unless json[0..2] == '"#<'

      # Let's hope they redefined to_hash.
      return obj.to_hash.to_json  if obj.respond_to?(:to_hash)

      raise "Can't convert object to JSON. Consider implementing #to_hash to #{obj.class.name}."
    end
  end
end
