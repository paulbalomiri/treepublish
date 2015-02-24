
_= lodash
###
  @summary Publish a collection, but include objects from linked collections
###


logging_f = (name,func, prefix="")->
  (args...)->
    console.log "#{prefix}#{name} called with args", args...
    ret= func.apply this, args
    console.log "#{prefix}#{name} finished with return: ", ret
    return ret
log_funcs= (prefix, o)->
  for key,val of o
    if _.isFunction val
      o[key] = logging_f key, val, prefix
      o[key].orig= val



observer_environment= new Meteor.EnvironmentVariable()
class TP.Observer 
  
  constructor_defaults:
    links:TP.links
    collections:TP.collections

    
  col_name: TP.get_collection_name
  col_get: TP.get_collection_by_name
  doc_id: (obj)->obj._id
  ###
    Arguments:
    @param session: The this object from apublish function
    @param  opts:
              *links [object|function] object containing the collections`link definitions indexed by their key. 
                If a function, than ut must return such an object upon invocation. Default is `TP.links
              * collections: [object|function] object containing the collections indexed by their key. 
                If a function, than ut must return such an object upon invocation. Default is TP.collections
  ### 
  constructor: (session , opts)->
    unless opts?
      opts= @constructor_defaults
    else
      opts= _.defaults {}, opts, @constructor_defaults
    if opts.with_logging
      @_init_logging_wrappers()
    @session=@s=session
    @_out_collection_name=opts._out_collection_name
    @cursors={}
    @stop_funcs=[]
    @hull= 
      deps:{}
      set:{}
      root_keys: {} 
    console.error "constuctor @hull:" ,@hull
    @add_missing_keys()
    @observe_external=[]
    @onStop =>
      @_stop()

    return this
  out_collection_name:(name)->
    if @_out_collection_name
      if _.isString(@_out_collection_name)
        return @_out_collection_name
      else if _.isFunction @_out_collection_name
        return @_out_collection_name(name)
    return name
  add_missing_keys:()->
    my_keys= _.union _.keys(this), _.keys(this.constructor::)
    ctx_keys= _.union _.keys(@s), _.keys(@s.constructor::)
    missing= _.difference ctx_keys, my_keys
    for key in missing
      @[key]=@s[key]
    my_keys= _.union _.keys(this), _.keys(@constructor::)
    ctx_keys= _.union _.keys(@s), _.keys(@s.constructor::)
    missing= _.difference ctx_keys, my_keys
    if missing? and missing.length
      
      console.warn "These options the from default publish context are not available in observer:", missing
  _stop:(ctx,args...)->
    for col_name, o in @observe_external
      o.stop()
  _observer_front_factory: (collection)->
     _.object ['added','changed', 'removed'].map (name)=>
      f= (id,args...)=>
        if (cursor_env=@cursors[collection])? and (id of cursor_env.suppress_propagation)
          console.log("Suppressed call : #{name} for #{collection}.#{id}")
          cursor_env.suppress_propagation[id]?=[]
          cursor_env.suppress_propagation[id].push f.bind(this, collection, id,args...,false)
        else
          @[name] collection,id,args..., false
      return [name,f]
  ###
    added_objects:
      a structure like:
      collection1:
        id1:true
        id2:true
        ...
      colection2: ...
  ###
  observe_dependent:(added_objects)->
    console.log "added_objects:",added_objects
    for collection, ids_o of added_objects
      ids=[]
      for id of ids_o
        ids.push id
      console.log "Watching #{collection},", ids.join(","), ids_o
      if ids.length
        cursor_env = @cursors[collection]
        unless cursor_env
          cursor_env = @cursors[collection]=
            id_to_handler:{}
            handlers:{}
            suppress_propagation:{}
            next_handler_id:0
        for id in ids
          if cursor_env.id_to_handler[id]?
            if  (suppressed_calls = cursor_env.suppress_propagation[id])?
              delete cursor_env.suppress_propagation[id]
              console.log("added a handler which we have already been watching")
              for suppressed_call in suppressed_calls
                suppressed_call()
            else
              console.error "Error, request to watch #{collection}._id=#{id} twice!!!"
        unwatched_ids= ids.filter (id) -> not cursor_env.id_to_handler[id]?
        if unwatched_ids.length
          cur= TP.get_collection_by_name(collection).find
            _id:
              $in: ids
          cursor_env.handlers[cursor_env.next_handler_id]= cur.observeChanges @_observer_front_factory(collection)
          unwatched_ids.map (id)->
            cursor_env.id_to_handler[id]=cursor_env.next_handler_id
          cursor_env.next_handler_id++

    return
  stop_observation:(removed_objects)->
    for collection, ids of removed_objects
      cursor_env= @cursors[collection]
      
      ids=[]
      for id of ids
        ids.push[id]
      if cursor_env?
        # First separate watched ids, from watched, but suppressed
        handler_to_ids={}
        handler_to_ids_suppressed={}
        for id, handler_id of cursor_env.id_to_handler
          if cursor_env.suppress_propagation[id]?
            handler_to_ids_suppressed[handler_id]?=[]
            handler_to_ids_suppressed[handler_id].push id
          else
            handler_to_ids[handler_id]?=[]
            handler_to_ids[handler_id].push id 

        #now go over the watched ids to decide whether to remove handler or suppress        
        for handler_id, watched_ids of handler_to_ids
          if (dif= _.difference watched_ids, ids).length
            # we still got some watched ids, so ju8st suppress the current set
            ids.map (inactive_id)->
              if cursor_env.suppress_propagation[inactive_id]?
                console.error "handler #{collection}.#{handler_id} got the request to suppress #{inactive_id} twice!"
              else
                cursor_env.suppress_propagation[inactive_id]=null
            console.log "keeping handler #{collection}.#{handler_id} suppressing ids #{ids}"
          else
            console.log("stopped handler #{collection}.#{handler_id} which was watching the ids #{watched_ids.join(',')} and suppressing ids#{_.keys().join(',')}")
            cursor_env.handlers[handler_id].stop()
            delete cursor_env.handlers[handler_id]    
            #remove all suppressed
            if (suppressed_ids= handler_to_ids_suppressed)?
              for id in suppressed_ids
                delete cursor_env.suppress_propagation[id]
                delete cursor_env.id_to_handler[id]
            #remove previously watched
            if watched_ids?
              for id in watched_ids
                delete cursor_env.id_to_handler[id]
            else
              console.error("Stopping sunscription for handler #{collection}.#{handler_id}, which already did not have any watched ids!")
      else
        console.error("Request to stop observation on unwatched collection (subscr=#{@_subscriptionHandle}, col=#{collection}, id=#{id})")
  
  added: (collection, id,fields, is_root=true)->
    if is_root
      _.deepSet @hull.root_keys, [collection, id], true
    _.deepSet @hull.set, [collection, id], fields
    console.error(@out_collection_name(collection), id,fields)
    @s.added @out_collection_name(collection), id,fields
    unless observer_environment.get()
      observer_environment.withValue true, =>
        [added,removed]= TP.outer_hull @hull
        console.log "added:" ,added, "removed:", removed
        if added[collection]?[id]?
          console.error("i am myself in the added collection! ") 
        @observe_dependent(added)
        if _.keys(removed).length
          @stop_observation(removed_objects)
          console.error "add operation for #{collection}._id=#{id}caused removals! "
  changed: (collection,id,fields, is_root=true)->
    for name, field of fields
      _.deepSet @hull.set, [collection, id, name], field
    @s.changed @out_collection_name(collection),id,fields
    unless observer_environment.get()
      observer_environment.withValue true, =>
        [added,removed]= TP.outer_hull @hull
        console.log "added:" ,added, "removed:", removed
        
        @observe_dependent(added)
        if is_root and removed[collection]?[id]?
          #don't remove observation from obects we did not subscribe ourselves
          delete removed[collection][id]
          keep= false
          for key of removed[collection]
            keep= true
          unless keep
            delete removed[collection]
        @stop_observation(removed)
    unless _.deepIn(@hull.set[collection][id])
      console.error("change of #{collection}.#{id} caused the object itself not to be in the result set any longer. fields:#{JSON.stringify(fields)}")
  removed:(collection,id,is_root=true)->
    if is_root
      delete @hull.root_keys[collection][id]
    obj=_.deepGet(@hull.root_keys, [collection])
    delete obj[id]
    @s.removed(@out_collection_name(collection), id)
    unless observer_environment.get()
      observer_environment.withValue true, =>
        [added,removed]= TP.outer_hull @hull
        console.error "REMOVE: is_root=#{is_root}" ,"added:" ,added, "removed:", removed
        @observe_dependent(added)
        
        if is_root

          #don't remove observation from obects we did not subscribe ourselves
          delete removed[collection][id]
          keep= false
          for key of removed[collection]
            keep= true
          unless keep
            delete removed[collection]
        @stop_observation(removed)
        if added? and _.keys(added).length
          console.error 'remove operation caused add to outer hull!'
  add_external_cursos:(curs)->
    unless _.isArray curs
      curs=[curs]
    for cur in curs
      #console.error "collection:" , cur.collection, 'cursor:', cur
      anon=new Meteor.Collection(null)
      #console.error anon
      #note that anonymous collection names are not accepted here
      # we need a really clean way to grab or assign an id->collection name
      try
        name= cur._getCollectionName()
      catch
        console.error( "Cannot extract name from cursor: ", cur, "in cursor array:", curs)
      @observe_external = cur.observeChanges
        added: (args...)=> @added name, args...
        removed:(args...)=> @removed name, args...
        changed: (args...)=> @changed name, args...
  _init_logging_wrappers:( callback_names)->

    @_callbacks={}
    
    #setup on_[before|after]_[added|changed|removed]
    #and wrap calls in event triggers
    callback_names?=['added','changed', 'removed']
    
    for method in callback_names
      @[method]= do(method=method)-> _.wrap Observer::[method], (orig, args...)->
        @_trigger("before_#{method}", args... )
        try
          ret=orig.apply this, args
        finally
          @_trigger("after_#{method}", args... )
        return ret
    callback_names= _.flatten callback_names.map (name)-> 
      ["before_#{name}", "after_#{name}"]
    for cb_name in callback_names
      @["on_"+cb_name]= do (name= cb_name)->
        (func)->
          @_callbacks[name]?=[]
          @_callbacks[name].push func
      @on_event = (func)->
          @_callbacks[null]?=[]
          @_callbacks[null].push func
    @_trigger= (name, args...)->
      if name of @_callbacks
        for cb in @_callbacks[name]
          cb.call(this, args...)
      if @_callbacks[null]?
        for cb in @_callbacks[null]
          cb.call(this,name, args...)


#log_funcs 'Observer:', TP.Observer::

if Meteor.isServer
  TP.publish = (opts, publish_f=opts.publish)->
    if _.isString opts
      opts=
        name:opts
    unless _.isFunction publish_f
      throw new Error('Either opts.publish or a second argument must be provided!') 
    pub_wrapper= (args...)->
      sub= this
      if opts.cb?
        opts.with_logging= true
      observer= new TP.Observer(sub, opts)
      if opts.cb?
        available_names= _.keys(observer).filter (cb_name)-> cb_name[0..2]=="on_" or true
        for key, func of opts.cb
          unless key in available_names
            throw new Error "No such callback name: #{key}. Available callbacks: [#{available_names.join(",")}]"
          observer[key] func
      ret= publish_f.apply observer, args
      if _.isObject ret
        unless _.isArray ret
          ret= [ret]
        observer.add_external_cursos(ret)
    Meteor.publish opts.name,  (args...)->
      #console.error('TP.publish function called')
      ret= pub_wrapper.call this, args...
      @ready()
      return





