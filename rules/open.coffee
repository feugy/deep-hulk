_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
{selectItemWithin, addAction, makeState, mergeChanges, getNextDoor} = require './common'
{detectBlips, findNextDoor} = require './visibility'

# Door opening rule
class OpenRule extends Rule

  # Only character that has doorToOpen property can open doors.
  # target must be the one referenced in this same doorToOpen property.
  #
  # @param actor [Item] the concerned actor
  # @param door [Item] the concerned door
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (actor, door, context, callback) =>
    # inhibit if waiting for deployment or other squad
    if actor.squad?.deployZone? or actor.squad?.waitTwist or actor.squad?.activeSquad? and actor.squad.activeSquad isnt actor.squad.name
      return callback null, null 
    return callback null, if actor.doorToOpen?.equals door then [] else null
      
  # Get the gemini door and open both.
  #
  # @param actor [Item] the concerned actor
  # @param door [Item] the concerned door
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (actor, door, params, context, callback) =>
    # avoid reopening already opened door
    unless door.closed
      actor.doorToOpen = null
      return callback null
      
    effects = []
    selectItemWithin actor.map.id, door, getNextDoor(door), (err, doors) =>
      return callback err if err?
      # opens all doors
      for candidate in doors when candidate?.type?.id is 'door'
        effects.push makeState candidate, 'closed', 'imageNum'
        candidate.closed = false
        candidate.imageNum -= 2
        candidate.transition = 'open'
        candidate.needClosure = actor.squad.isAlien and (candidate.zone1? or candidate.zone2?)
        @saved.push candidate
        
      console.log "#{actor.name or actor.kind} (#{actor.squad.name}) opens door at #{door.x}:#{door.y}"
      # search for other door to open (only possible for dreadnoughts)
      candidates = [actor]
      isDreadnought = actor.kind is 'dreadnought' and actor.revealed
      # dreadnought have 2 range, because they can open with any of their parts
      range = if isDreadnought then 2 else 1
      selectItemWithin actor.map.id, {x:actor.x-1, y:actor.y-1}, {x:actor.x+range, y:actor.y+range}, (err, items) =>
        return callback err if err?
        # put actor and door into rule.saved to allow merge in detectBlipd
        @saved.push actor, door
        # don't forget to take in account modified doors
        mergeChanges items, @
        
        actor.doorToOpen = findNextDoor (if isDreadnought then actor.parts.concat [actor] else actor), items
        detectBlips actor.map.id, @, effects, (err) =>
          return callback err if err?
          addAction 'open', actor, effects, @, (err) =>
            return callback err if err?
            # toggle deployement if needed (aliens cannot)
            return callback() unless (door.zone1? or door.zone2?) and not actor.squad.isAlien
            # select relevant zone regarding actor position
            switch door.imageNum 
              # vertical door, zone1 is left, zone2 is right
              when 6, 7, 14, 15
                zone = if actor.x is door.x-1 then door.zone2 else door.zone1
              when 18, 19 
                zone = if actor.x is door.x then door.zone2 else door.zone1
              # horizontal door, zone1 is top, zone2 is bottom
              when 2, 3
                zone = if actor.y is door.y-1 then door.zone1 else door.zone2
              when 10, 11
                zone = if actor.y is door.y then door.zone1 else door.zone2
            # no zone found
            return callback() unless zone?
            # inhibit actor actions
            actor.squad.deployZone = zone
            console.log "#{actor.squad.name} enter deploy zone #{zone}"
            # ask alien player to deploy this zone
            id = actor.map.id.replace 'map-', ''
            return Item.where('type', 'squad').where('isAlien', true).regex('_id', "squad-#{id}-").exec (err, [alien]) =>
              return callback err if err?
              return callback() unless alien?
              unless alien.deployZone?
                alien.deployZone = zone
              else if -1 is alien.deployZone.indexOf zone
                alien.deployZone += ",#{zone}"
              @saved.push alien
              callback()
      
module.exports = new OpenRule()