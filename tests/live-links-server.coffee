G= share.G
# publish the  base collection 
Meteor.publish 'base-collections', ->
    ret=  share.col_names.map (name)->
      TP.collections[name].find()
tp_publish_opts=
  name: 'result-collections'
  _out_collection_name: (name)->"#{name}#{G.result_appendix}"
  cb:
    on_event: (event_name, collection,id,fields,is_root)-> 
      if event_name[0..4]=='after'
        console.log("subscription: #{@_subscriptionHandle} ,#{event_name} : col=#{@out_collection_name collection}, id: #{id} ")
        console.log("watched_cursors:",   @cursors)
      share.oplog.insert
        op: event_name
        subscription_id: @_subscriptionHandle
        collection:collection
        id:id
        fields: fields
        is_root:is_root 
#publish the result collections 
TP.publish tp_publish_opts , (collection,ids)->
  if collection?
    unless _.isArray collection
      collections= collection.split(',')
    else
      collections= collection
  else
    collections= share.col_names
  ret= collections.map (collection)->
    col= TP.get_collection_by_name collection
    console.log "publishing collection:", collection 
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