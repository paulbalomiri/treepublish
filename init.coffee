
_= lodash
unless Match.All?
  Match.All= (patterns...)->
    Match.Where (o)->
      for pattern in patterns
        check o, pattern



@TP=TP=
  links:default_links= {}
  collections:default_collections= {}
  default_link_spec: true
  
  _collection_getters:do ->
    ret= []
    if ET?.get_collection_by_name
      ret.push ET.get_collection_by_name
    else
      ret.push (name)->
        if TP.collections?[name]?
          return TP.collections[name]
        return
    if Meteor.isClient
      ret.push (name)->Meteor.connection._stores[names]
    return ret
  _collection_name_getters: do -> 
    ret=[(col)->col.name or col._name]
    if ET?.get_collection_name?
      ret.push ET.get_collection_name
    return ret  
  get_collection_name:(name)->
    for getter in TP._collection_name_getters
      if(ret= getter(name))
        return ret
    return
  get_collection_by_name: (name)->
    for getter in TP._collection_getters
      if(ret= getter(name))
        return ret
    return
  _links_definition_getters:[
    (col_name)-> TP.links?[col_name]
  ]
  get_links_definition:(collection_name)->
    for getter in TP._links_definition_getters
      if(ret= getter(collection_name))
        return ret
    return
  _collection_type_getters:do ->
    if ET?.get_default_collection?
      [
        ET.get_default_collection
      ]
    else
      [
        (type)->
          if _.isString type
            type= type.split ":"
          if type[type.length-1] == "ref"
            return type[0...-1].join("_") 
          else
            return type.join("_")
      ]
  get_collection_by_type: (type)-> 
    for getter in TP._collection_type_getters
      if(ret= getter(type))
        return ret
    return
  get_collection_name_from_link_spec: (link_spec)->
    if _.isBoolean link_spec
      return '__any__'
    else if _.isString link_spec
      #this is not mandatory. it depends on the target
      return '__any__'
    else if _.isObject link_spec
      if TP.get_collection_name(link_spec)
        return '__any__'
      else if link_spec?.target?.default?
        return '__any__'
      if link_spec.target?.fixed?
        if _.isString link_spec.target.fixed
          return link_spec.target.fixed
        else
          return TP.get_collection_name(link_spec.target.fixed)
      else if link_spec.type?
        #type can only be resoved with an object
        return '__any__'

  links_for:(links_def, doc, subscription_context)->
    unless links_def? and doc?
      return 
    ret= undefined
    for link_field, link_def of _.pick links_def, _.intersection(_.keys(links_def), _.keys(doc)) 
      link= doc[link_field] or {}
      if _.isString link 
        link=
          link_id:link 
      if _.isFunction link_def
        link_def= link_def.call subscription_context, link_def, doc, link_field, links_def
      if _.isBoolean link_def
        unless link_def and ( link.link_collection? or link.type?)
          continue
      else if _.isString link_def
        link?={}
        _.extend link,
            link_collection: link_def

      else if _.isObject link_def
        if link_def instanceof Meteor.Collection
          link.link_collection= link_def._name
        else
          if _.isFunction(link_def.before)
            link_def.before.call subscription_context, link_def, doc,link_field, links_def
          for [setting_name,transform] in [['target', (x)-> _.isString(x) and x or x._name ], ['type', (x)->TP.get_collection_by_type(x)]]
            setting= link_def[setting_name]
            if (setting)?
              if _.isString setting
                link.link_collection ?= transform setting
              else if _.isObject setting
                if setting.fixed
                  link.link_collection= transform setting.fixed
                else if setting.default?
                  link.link_collection?=transform setting.default   

          if link_def.defaults?
            _.defaults link, link_def.defaults
          if link_def.extend?
            _.extend link, link_def.extend
      else if _.isFunction link_def
        link
      if _.isFunction link_def?.after
        link_def.after.call subscription_context, link_def, doc,link_field, links_def
      unless link.link_collection?
        if link.type?
          link.link_collection= TP.get_collection_by_type link.type
      unless link.link_collection?
        console.error('Collection or type+default collection missing: could not resolve link', link)
        continue
      ret?={}
      ret[link_field] = link
    return ret
  outer_hull_default_options: do ->
    max_depth: 5000
    links: default_links
    collections: default_collections
  resolve_link:(link, opts, callback)->
    try
      ret= TP.get_collection_by_name(link.link_collection)?.findOne(link.link_id)
    catch e
      error = e 
    finally
      if callback?
        callback(e,ret)
        return 
    return ret

  outer_hull: (opts)->
    _.defaults opts,
      root_keys:{}
      deps:{}
      set:{}
      failed_resolutions:{}
    TP._outer_hull opts
  _set_root_deps:(root_keys, deps )->
    for collection, o1 of deps 
      for id, incoming of o1
        if _.deepGet(incoming, ['root'] )? != (is_root= _.deepGet(root_keys,[collection,id]))
          if is_root
            incoming.root= true
          else
            delete incoming.root
    for collection, o1 of root_keys
      for id, incoming of o1
        _.deepSet deps, [collection,id,'root'], true

  _outer_hull: (opts)->
    invocation_id=Random.id()
    [set, deps,  root_keys, failed_resolutions]= [opts.set, opts.deps, opts.root_keys, opts.failed_resolutions]
    [added,removed]=[{},{}]
    TP._set_root_deps(root_keys,deps)
    work= _.cloneDeep set
    while  _.keys(work).length
      old_work=work
      work={}
      stoppers= {}
      for collection, objects  of old_work
        for key,obj of objects
          links= TP.links_for TP.get_links_definition(collection), obj
          ##Add links to new objects
          for prop, val of links
            unless _.deepIn set ,[val.link_collection, val.link_id]
              dep_path= [
                          val.link_collection 
                          val.link_id
                          collection
                          key
                          prop
                        ]
              have_dep = _.deepGet deps, dep_path
              unless have_dep? 
                dep = TP.resolve_link val, opts
                unless dep?
                  failed_resolutions[val.collection_id] = 
                    from_link: val
                    message: "Link resolution attempt returned undefined/null"
                else
                  _.deepSet deps, dep_path, 1
                  new_path= [val.link_collection, val.link_id]
                  unless _.deepIn set, new_path
                    console.log "#{invocation_id}added:" , _.deepGet(set, new_path),new_path...
                    _.deepSet added, new_path , true
                    _.deepSet set, new_path , _.omit(dep,'_id')
                    console.log "set to" , _.deepGet(set, new_path)
                    _.deepSet work, new_path, dep
    debugger
    ##now check removals
    work= _.cloneDeep set

    while _.keys(work).length
      old_work=work
      work= {}
      for collection ,o1 of old_work
        for id, obj of o1
          had_incoming=
            any:false
            col:false
            obj:false            
          if (incoming = _.deepGet deps, [collection,id])
            for in_collection, o2 of incoming
              if in_collection=='root'
                had_incoming.any=true
                continue
              for in_id ,o3 of o2
                link_source= TP.links_for TP.get_links_definition(in_collection), _.deepGet set, [in_collection, in_id]
                for in_prop of o3
                  link=_.deepGet(link_source, in_prop)
                  if _.isEqual [link?.link_collection, link?.link_id],[collection,id]
                    had_incoming.col= had_incoming.obj= had_incoming.any= true
                  else 
                    delete o3[in_prop]
                unless had_incoming.obj
                  delete o3[in_id]
                had_incoming.obj= false
              unless had_incoming.col
                delete incoming[collection]
              had_incoming.col= false
          unless had_incoming.any 
            my_links= TP.links_for TP.get_links_definition(collection), _.deepGet set, [collection,id]
            # add everyone who depends on us back to the work list
            for prop, link of my_links
              prop_path= [ link.link_collection,link.link_id]
              _.deepSet work, prop_path , _.deepGet set, prop_path
            if set[collection]?[id]?
              delete set[collection]?[id]
            unless _.keys(set[collection]).length
              delete set[collection]
            _.deepSet removed, [collection,id], true
    for collection, o1 in added
      for id in o1
        if removed[collection]?[id]?
          console.log("object found in added and in removed. Removing from both")
          for obj in [added, removed]
            if obj[collection]?[id]?
              delete obj[collection][id]
              unless _.keys(obj[collection]).length
                delete obj[collection]      
    console.error "outer hull: ADDED:", added, "removed:", removed
    return [added,removed]
