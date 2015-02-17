
_= lodash
###
  @summary Publish a collection, but include objects from linked collections
###



TP.outer_hull = (object)->
class TP.Observer 
  
  constructor_defaults:{}
    
  col_name: TP.get_collection_name
  col_get: TP.get_collection_by_name
  doc_id: (obj)->obj._id
  ###
    Arguments:
    @param session: The this object from apublish function
    @param  opts:
              * col_name(collecttion) given a collection return it's name (default:TP.get_collection_name)
              * col_get(name) given a name return the corresponding collection (default: TP.get_collection_by_name)
              * doc_id(doc): function to retrieve the id from a given object
  ###
  constructor: (session , opts)->
    unless opts?
      opts= @constructor_defaults
    else
      opts=_.defaults _.cloneDeep(opts), @constructor_defaults
    _.extend this, _.pick opts, ['col_name', 'col_get', 'doc_id']
    @session=@s=@
    @observe={}
  stop:->
    for col_name, o of @observe
      observe[@].stop()
  observe_cursor:(cur)->
    observe
  added:(collection, id,fields)->
    links= TP.links_for(collection, _extend {_id:id}, fields)
  changed:(collection,id,fields)->
  removed:(collection,id)->
if Meteor.isServer
  TP.publish = (opts, publish_f=opts.publish)->
    
    unless _.isFunction publish_f
      throw new Error('Either opts.publish or a second argument must be provided!') 
    pub_wrapper= (args...)->
      sub= this
      observer= new TP.observer(sub)
      orig_funcs= _.pick sub, ['added,changed, removed']
      _.extend  sub , 
          added: _.wrap sub.added , (orig, collection,id,fields)->
            orig.call this, collection,id,fields
          changed: _.wrap sub.changed , (orig, collection,id,fields)->
            orig.called this, collection,id,fields
          removed: _.wrap sub.removed , (orig, id)->
            orig.apply this, id
      ret= publish_f.apply sub,this
      _.extend sub, orig_funcs
      unless _.isArray ret
        ret= [ret]
      #for ret_cur in ret
      #  ret.observe

      @onStop ->
        observer.stop()
        
      return ret




