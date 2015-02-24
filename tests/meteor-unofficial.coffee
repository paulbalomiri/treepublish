
_.lodash

Tinytest.add "Test availability of _suppress_initial on Meteor.Collection.observe/observeChanges", (test)->
  my_collection = new Meteor.Collection null
  
  initial_ids = _.range(4).map (i)->
    my_collection.insert
      idx:i
  cur = my_collection.find()

  seen_ids_wo_suppress=[]
  wo_handle= cur.observeChanges
    added: (id)-> seen_ids_wo_suppress.push(id)

  seen_ids_with_suppress=[]
  with_handle= cur.observeChanges
    _suppress_initial:true
    added: (id)-> seen_ids_with_suppress.push(id)
  
  added_ids= _.range(initial_ids.length, initial_ids.length+4).map (i)-> 
    my_collection.insert
      idx: i

  test.equal seen_ids_wo_suppress, [initial_ids...,added_ids...] , 'somehow Not all inserted elements have been seen'
  
  test.equal seen_ids_with_suppress, added_ids, "_suppress_initial did not observe exavtly the objects inserted after observation point"

test_collection=new Meteor.Collection('test_collection') 
  
Tinytest.add "test cursor-> collection name", (test)->
  col = test_collection
  cur = col.find()
  test.equal cur._getCollectionName(), 'test_collection'

#if Meteor.isServer
