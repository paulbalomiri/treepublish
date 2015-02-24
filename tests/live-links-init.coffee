_= lodash
###
makes a graph definition.
Collections are provide
###

share.col_names=  ['A','B', 'C']
share.link_prop_names= ['l0', 'l1', 'l2', 'l3']
share.G= G =
  result_appendix: "_result"

share.test_case_result_mixin = 
  eqGraph: (g1, g2, msg)->
      n1= G.normalize_link_values _.cloneDeep g1, true
      n2= G.normalize_link_values _.cloneDeep g2, true
      @equal n1,n2, msg
Tinytest.addWithGraph = (name,g,f)->
  my_f=(args...,cb)->
    f(args...)
    cb()
  Tinytest.addWithGraphAsync( name, g, my_f )

Tinytest.addWithGraphAsync = ( name, g, f )->
  Tinytest.addAsync name,  (test, args...)->
    G.reset_db()
    G.insert_links(g)
    _.extend test, share.test_case_result_mixin
    f.call this,test,args...    

do->

  links_per_collection= 10;
  TP.collections= _.object share.col_names.map (name)->
    [name, new Meteor.Collection(name)]
  TP.links=  _.object _.keys(TP.collections).map (col_name)->
    def={}
    for prop_name in share.link_prop_names
      def[prop_name]=true
    [col_name ,  def ]



###
normalize_linkfields transforms any of the following to correct link fields
links:
  A: ["b2", "b3","b4"] #(links to objects in collection b with idx value 2,3,4 e.t.c)

link definitions in classical form are left untouched
links:
  A:
    l1: #  this is the link property
      link_collection: "B"
      link_id: #whatever linkid is present in b
      print_name: "Whatever name you assign to this link"
    l2: ...

###

link_short_name_rex=/([A-Za-z0-9]*[A-Za-z])([0-9]+)/

G.normalize_link_values= (links, normalize_objects=false )->
  for collection,link_props_array of links
    unless _.isArray link_props_array
      if _.isString link_props_array
        links[collection]=link_props_array= link_props_array.split(',')
      else
        links[collection]=link_props_array=[link_props_array]
    for link_props, link_props_array_idx in link_props_array
      if _.isString link_props
        if link_props==""
          link_props= null
        else
          link_props= [link_props.split(',')...]
      if _.isArray link_props
        link_props = _.object link_props.map (val,idx)->
          if idx >= share.link_prop_names.length
            throw new Error("not enough link properties to map link values #{link_props.join(',')} to #{share.link_prop_names.join(',')}")
          return [share.link_prop_names[idx], val]
        for link_prop,link_val of link_props
          if link_val=="" or _.isNull(link_val)
            link_props[link_prop]= null
            continue # node without links
          fields= link_short_name_rex.exec link_val
          unless fields
            throw new Error( "Cannot extact collection/idx from short name #{link_val}")
          unless target_collection= TP.get_collection_by_name  fields[1].toUpperCase()
            throw new Error "Could not find collection/extract colection name from #{link_val}. Expecting name to be #{field[1].toUpperCase}"
          unless target= target_collection.findOne {idx: fields[2]%1}
            target_idx= fields[2]/1
          l=
            link_collection: TP.get_collection_name target_collection
          if target?
            l.link_id=target._id
          else
            l.target_idx= target_idx
          link_props[link_prop]=l
      else if _.isObject(link_props) and normalize_objects
        #this is nessesary for equivalence comparisions
        for prop, val of link_props
          if val.link_id
            ret= TP.get_collection_by_name(val.link_collection).findOne(val.link_id)
            if ret?.idx?
              val.target_idx=ret.idx
            delete val.link_id
      link_props_array[link_props_array_idx]= link_props
      
  return links
G.set_graph= (g)->
  G.reset_db()
  G.insert_links(g)
G.insert_links= (links)->
  ret= []    
  links= G.normalize_link_values _.cloneDeep links
  idx = {}
  update_ids= {}
  for collection , link_props_array of links
    col_obj= TP.get_collection_by_name(collection)
       
    for link_props, link_props_array_idx in link_props_array
      idx[collection] ?= col_obj.find().count()
      obj= 
        idx:idx[collection]
      idx[collection]++
      ret_idx=ret.length
      ret.push obj
      if link_props?
        for link_prop, val of link_props
          obj[link_prop]=val  
          if link_prop of TP.links[collection] 
            unless val.link_id?
              o= _.deepGet update_ids, [collection,"idx#{obj.idx}"] , {}
              o.ret_idx?=ret_idx
              o.props?=[]
              o.props.push link_prop 
      obj._id= col_obj.insert obj
  for collection, o1 of update_ids
    for idx, o of o1
      mod=
        $set:{}
        $unset:{}
      obj= ret[o.ret_idx]
      for prop in o.props 
        mod.$set["#{prop}.link_id"]=obj[prop].link_id = TP.get_collection_by_name(obj[prop].link_collection).findOne({idx:obj[prop].target_idx})._id
        mod.$unset["#{prop}.target_idx"]=true
        delete obj[prop].target_idx
      TP.get_collection_by_name(collection).update obj._id , mod
  return ret

G.change_link= (node, new_node)->
  unless new_node?
    return remove_link(node)
  [node,property]=node.split('.')
  unless property?
    property= share.link_prop_names[0]
  else unless share.link_prop_names.indexOf(property) >=0
    property= share.link_prop_names[property/1]
  [u,v]=[{},{}]
  [u.name,u.col_name,u.idx]= link_short_name_rex.exec node
  [v.name,v.col_name,v.idx]= link_short_name_rex.exec new_node
  v.obj= TP.get_collection_by_name(v.col_name).findOne
      idx:v.idx/1
  set_mod={}
  set_mod[property]=
    link_id:v.obj._id
    link_collection:v.col_name 

  u.col= TP.get_collection_by_name(u.col_name)
  u.col.update u.col.findOne({idx:u.idx/1})._id,  
    $set:set_mod
G.remove_link= (edge)->
  [node,property]=edge.split('.')
  unless property?
    property= share.link_prop_names[0]
  else unless share.link_prop_names.indexOf(property) >=0
    property= share.link_prop_names[property/1]
  u={}
  [u.name,u.col_name,u.idx]= link_short_name_rex.exec edge
  collection=TP.get_collection_by_name(u.col_name)
  u.obj=collection.findOne({idx:u.idx/1})
  mod =
     $unset: _.object [[property, ""]] 

  collection.update _.pick(u.obj, '_id') , mod
   
G.get_graph= (collection_name_appendix="")->
  if _.isBoolean(collection_name_appendix)
    collection_name_appendix= G.result_appendix
  ret= {}
  props= [share.link_prop_names...] 
  for name in share.col_names
    col= TP.get_collection_by_name(name + collection_name_appendix)
    cur= col.find()
    if cur.count()>0
      ret[name]=cur.fetch().map (doc)->
        doc= _.pick doc, props
        if _.keys(doc).length==0
          null
        else
          doc
  return ret

G.equivalent_graphs= (g1, g2)->
  n1= G.normalize_link_values g1, true
  n2= G.normalize_link_values g2, true
  return _.isEqual g1,g2

G.reset_db= ()->
  for collection in   share.col_names.map( (name)-> TP.get_collection_by_name(name))
    collection.find().forEach (obj)->
      collection.remove(obj._id)

