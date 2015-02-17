
unless Match.All?
  Match.All= (patterns...)->
    Match.Where (o)->
      for pattern in patterns
        check o, pattern



@TP=TP=
  links:{}
  default_link_spec: true
  _collection_getters:do ->
    ret= []
    if ET?.get_collection_by_name
      ret.push ET.get_collection_by_name
    else
      ret.push (name)->
        if collections?[name]?
          return collections[name]
        return
    if Meteor.isClient
      ret.push (name)->Meteor.connection._stores[a]
    return ret
  _collection_name_getters: do -> 
    if ET?.get_collection_name?
      [ET.get_collection_name]
    else 
      [(col)->col.name or col._name]
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
        unless link_def and ( link.collection? or link.type?)
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
  outer_hull_default_options:
    max_depth: 5000
  outer_hull:(collection, id,options={})->




