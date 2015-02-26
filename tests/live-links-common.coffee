_= lodash
G= share.G


Tinytest.add "clean test db check", (test)->
  
  G.reset_db()
  for col_name in share.col_names
    test.isTrue  TP.get_collection_by_name(col_name).find().count()==0,  "collection #{col_name} is not emplty!"

Tinytest.add "test_normalization", (test)->
  test.equal G.normalize_link_values({A:["b2", "b1"]}),
    A:[
          idx_offset:0
          l0:
            link_collection:"B"
            target_idx:2
        ,
          idx_offset:1
          l0:
            link_collection:"B"
            target_idx:1
      ]

  test.equal G.normalize_link_values({B:["a2", "c1", "c3"], A:[["a1","b1"], "c3", ['a2','a3']] }),
    B: [
        idx_offset:0
        l0:
          link_collection: 'A'
          target_idx: 2 
      ,
        idx_offset:1
        l0:
          link_collection: 'C'
          target_idx: 1 
      ,
        idx_offset:2
        l0:
          link_collection: 'C'
          target_idx: 3 
      ]
    A:[
        idx_offset:0
        l0:
          link_collection: 'A'
          target_idx: 1
        l1:
          link_collection: 'B'
          target_idx: 1
      , 
        idx_offset:1 
        l0:
          link_collection: 'C'
          target_idx: 3 
      ,
        idx_offset:2
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
        idx_offset:0
        l0:
          link_collection:'B'
          target_idx: 0
      ]
    B: [
      idx_offset:0
    ]
  test.equal G.normalize_link_values({A:['B0'], B:['']},true), g, 'two graphs with nodes in different collections'
  test.equal G.normalize_link_values({A:['B0'], B:['']},true), g, 'two graphs with nodes in different collections'
  test.isTrue G.equivalent_graphs {A:"B0;B2", B:";;"}, {A:["B0", "B2"], B:[null,null,null]}, 'different representations of empty nodes'
g= 
  A:['B0']
  B:['']
Tinytest.addWithGraph 'text change_link', g,  (test)->
  G.change_link('B0.0','A0')
  test.eqGraph G.get_graph() , {A:'B0', B:'A0' }, "Graqh mutation did not yield expected graph"
  G.remove_link('B0.0')
  test.eqGraph G.get_graph(),g
Tinytest.add "final reset_db 1",->
  G.reset_db()
  

