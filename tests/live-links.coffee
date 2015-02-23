_= lodash
###
makes a graph definition.
Collections are provide
###

col_names= ['A','B', 'C']
link_prop_names= ['l0', 'l1', 'l2', 'l3']
share.G= G =
  result_appendix: "_result"

  
do->

  links_per_collection= 10;
  TP.collections= _.object col_names.map (name)->
    [name, new Meteor.Collection(name)]

  if Meteor.isClient
    Meteor.subscribe 'base-collections'
    _.extend TP.collections, _.object col_names.map (name)->
      res= "#{name}#{G.result_appendix}"
      [res, new Meteor.Collection(res)]
      Meteor.subscribe (res)   
  else
    Meteor.publish 'base-collections', ->
      ret=  col_names.map (name)->
        TP.collections[name].find()
    tp_publish_opts=
      name: 'result-collections'
      out_collection_name: (name)->"#{name}#{G.result_appendix}" 
    TP.publish tp_publish_opts , (collection,ids)->
      if collection?
        unless _.isArray collection
          collections= collection.split(',')
        else
          collections= collection
      else
        collections= col_names
      ret= collections.map (collection)->
        col= TP.get_collection_by_name collection
        console.log "publishing vollection:", collection 
        unless ids
          return col.find()
        else if _.isString ids
          return col.find(ids)
        else
          return col.find
            _id:
              $in: ids
    for name, collection of TP.collections
      collection.allow
        insert:->true
        update:->true
        remove:->true
  TP.links=  _.object _.keys(TP.collections).map (col_name)->
    def={}
    for prop_name in link_prop_names
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
          if idx >= link_prop_names.length
            throw new Error("not enough link properties to map link values #{link_props.join(',')} to #{link_prop_names.join(',')}")
          return [link_prop_names[idx], val]
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
    property= link_prop_names[0]
  else unless link_prop_names.indexOf(property) >=0
    property= link_prop_names[property/1]
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
    property= link_prop_names[0]
  else unless link_prop_names.indexOf(property) >=0
    property= link_prop_names[property/1]
  u={}
  [u.name,u.col_name,u.idx]= link_short_name_rex.exec edge
  collection=TP.get_collection_by_name(u.col_name)
  u.obj=collection.findOne({idx:u.idx/1})
  mod =
     $unset: _.object [[property, ""]] 

  collection.update _.pick(u.obj, '_id') , mod
   
G.load_graph= (collection_name_appendix="")->
  ret= {}
  props= [link_prop_names...] 
  for name in col_names
    col= TP.get_collection_by_name(name)
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
  for collection in   col_names.map( (name)-> TP.get_collection_by_name(name))
    collection.find().forEach (obj)->
      collection.remove(obj._id)

Tinytest.addWithGraph = ( name, g, f )->
  Tinytest.add name,  (test, args...)->
    G.reset_db()
    G.insert_links(g)
    test.eqGraph = (g1, g2, msg)->
      n1= G.normalize_link_values _.cloneDeep g1, true
      n2= G.normalize_link_values _.cloneDeep g2, true
      test.equal n1,n2, msg
    f.call this,test,args...

Tinytest.add "clean test db check", (test)->
  
  G.reset_db()
  for col_name in col_names
    test.isTrue  TP.get_collection_by_name(col_name).find().count()==0,  "collection #{col_name} is not emplty!"

Tinytest.add "test_normalization", (test)->
  test.equal G.normalize_link_values({A:["b2", "b1"]}),
    A:[
          l0:
            link_collection:"B"
            target_idx:2
        ,
          l0:
            link_collection:"B"
            target_idx:1
      ]

  test.equal G.normalize_link_values({B:["a2", "c1", "c3"], A:[["a1","b1"], "c3", ['a2','a3']] }),
    B: [
        l0:
          link_collection: 'A'
          target_idx: 2 
      ,
        l0:
          link_collection: 'C'
          target_idx: 1 
      ,
        l0:
          link_collection: 'C'
          target_idx: 3 
      ]
    A:[
        l0:
          link_collection: 'A'
          target_idx: 1
        l1:
          link_collection: 'B'
          target_idx: 1
      ,  
        l0:
          link_collection: 'C'
          target_idx: 3 
      ,
        l0:
          link_collection: 'A'
          target_idx: 2
        l1:
          link_collection: 'A'
          target_idx: 3
      
      ]
Tinytest.add 'test insert operation' , (test)->
  g=
    A:[ 'B0', 'C0']
    C:[ 'A0', 'B1']
    B:[ ['A0', 'C1'] , 'B1']
  ret= G.insert_links g
  test.equal ret.length,  _.values(g).reduce( ((prev,n)-> prev+n.length) , 0) ,
    "The inserted node count is not the same as in the input graph"
  idx=0
  for col_name, entries of g
    col= TP.get_collection_by_name col_name
    for obj_idx in _.range(entries.length)
      db_obj= col.findOne(ret[idx]._id)
      test.equal ret[idx], db_obj, "object returned from index is not the same as in the collection"
      test.equal db_obj.idx, obj_idx, "doc in collection does not have the expected index"
      test.equal db_obj._id, ret[idx]._id, "doc in collection does not have the same _id as insert_links._id"
      
      idx++


Tinytest.add 'test insert operation containing linkless nodes' , (test)->
  G.reset_db()
  ret= G.insert_links
    A: ['','B0']
    B: ['', 'A0']

  test.equal _.omit(ret[0], '_id'), {idx:0} ,'Node A0 is not empty'
  test.equal _.omit(ret[2], '_id'), {idx:0}, 'Node B0 is not empty'
  test.equal _.omit(ret[1], '_id'), {idx:1, l0:{link_id: ret[2]._id, link_collection:'B'}}, 'A1 is not pointing to B0'
  test.equal _.omit(ret[3], '_id'), {idx:1, l0:{link_id: ret[0]._id, link_collection:'A'}}, 'Node B1 is not pointing to A0'


Tinytest.add 'Test graph equivalence Function', (test)->
  G.reset_db()
  test.isTrue G.equivalent_graphs {}, {}, 'two empty graphs'
  test.isTrue G.equivalent_graphs {A:['']}, {A:['']}, 'two graphs with linkless nodes'
  test.isFalse G.equivalent_graphs {A:['']}, {B:['']}, 'two graphs with nodes in different collections'
  g=
    A:[
        l0:
          link_collection:'B'
          target_idx: 0
      ]
    B: [null]
  test.equal G.normalize_link_values({A:['B0'], B:['']},true), g, 'two graphs with nodes in different collections'
  test.equal G.normalize_link_values({A:['B0'], B:['']},true), g, 'two graphs with nodes in different collections'
  test.isTrue G.equivalent_graphs {A:"B0,B2", B:",,"}, {A:["B0", "B2"], B:[null,null,null]}, 'different representations of empty nodes'
g= 
  A:['B0']
  B:['']
Tinytest.addWithGraph 'text change_link', g,  (test)->
  G.change_link('B0.0','A0')
  test.eqGraph G.load_graph() , {A:'B0', B:'A0' }, "Graqh mutation did not yield expected graph"
  G.remove_link('B0.0')
  test.eqGraph G.load_graph(),g
  

