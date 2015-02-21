
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
  constructor: logging_f 'constructor', (session , opts)->
    unless opts?
      opts= @constructor_defaults
    else
      opts= _.defaults {}, opts, @constructor_defaults
    @session=@s=session
    @_out_collection_name=opts.out_collection_name
    @cursors={}
    @stop_funcs=[]
    @hull= 
      deps:{}
      set:{}
      root_keys: {}  
    @add_missing_keys()
    
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
    for col_name, o of @observe
      o.stop()
  _observer_front_factory: (collection)->
     _.object ['added','changed', 'removed'].map (name)=>
      f= (id,args...)=>
        if (cursor_env=@cursors[collection])? and (id of cursor_env.suppress_propagation)
          console.log("Suppressed call : #{name} for #{collection}.#{id}")
          cursor_env.suppress_propagation[id]= f.bind(this, id,args...,false)
        else
          @[name] id,args..., false
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
    for collection, ids of added_objects
      ids=[]
      for id of ids
        ids.push[id]

      if ids.length
        cursor_env = @cursors[collection]
        unless cursor_env
          cursor_env = @cursors[collection]=
            id_to_handler:{}
            handlers:{}
            suppress_propagation:{}
            next_handler_id:0
        for id of ids
          if cursor_env.id_to_handler[id]?
            unless  _.isUndefined(suppressed_call = cursor_env.suppress_propagation[id])
              delete cursor_env.suppress_propagation[id]
              console.log("added a handler which we have already been watching")
              suppressed_call?()
            else
              console.error "Error, request to watch #{collection}._id=#{id} twice!!!"
          else
            
            cur= TP.get_collection_by_name(collection).find
              _id:
                $in: ids
            cursor_env.handlers[cursor_env.next_handler_id]= cur.observeChanges _observer_front_factory(collection)
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
        console.error("Request to stop observation on unwatched collection")
  added: (collection, id,fields, is_root=true)->
    if is_root
      _.deepSet @hull.root_keys, [collection, id], true
    _.deepSet @hull.set, [collection, id], fields
    [added,removed]= TP.outer_hull @hull
    @s.added @out_collection_name(collection), id,fields
    for collection,ids of added
      for id of ids
        @s.added(@out_collection_name(collection), id, @hull.set[collection][id])

    if _.keys(removed).length
      console.error "add operation for #{collection}._id=#{id}caused removals! "
  changed: (collection,id,fields, is_root=true)->
    for name, field of fields
      _.deepSet @hull.set, [collection, id, name], field
    [added,removed]= TP.outer_hull @hull
    for collection,ids of added
      for id of ids
        @s.added(@out_collection_name(collection), id, @hull.set[collection][id])
    for collection,ids of removed
      for id of ids
        @s.removed(@out_collection_name(collection), id)
    if _.deepIn(@hull.set[collection][id])
      @s.changed @out_collection_name(collection),id,fields
    else
      console.error("change of #{collection}.#{id} caused the object itself noty to be in the result set any longer. fields:#{JSON.stringify(fields)}")
  removed:(collection,id,is_root=true)->
    if is_root
      delete @hull.root_keys[collection][id]
    obj=_.deepGet(@hull.root_keys, [collection])
    delete obj[id]
    [added,removed]= TP.outer_hull @hull
    for collection,ids of removed
      for id of ids
        @s.removed(@out_collection_name(collection), id)
    if added? and _.keys(added).length
      console.error 'remove operation caused add to outer hull!'
#log_funcs 'Observer:', TP.Observer::

if Meteor.isServer
  TP.publish = (opts, publish_f=opts.publish)->
    if _.isString opts
      opts=
        name:opts
    unless _.isFunction publish_f
      throw new Error('Either opts.publish or a second argument must be provided!') 
    pub_wrapper= (args...)->
      console.error("pubwrapper called")
      sub= this
      observer= new TP.Observer(sub, opts)
      ret= publish_f.apply observer, args
      unless _.isArray ret
        ret= [ret]
      #for ret_cur in ret
      #  ret.observe
    Meteor.publish opts.name,  (args...)->
      console.error('TP.publish function called')
      pub_wrapper.call this, args...
      return




