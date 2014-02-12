_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
{selectItemWithin, addAction} = require './common'
{detectBlips} = require './visibility'

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
    # inhibit if wanting for deployment
    return callback null, null if actor.squad?.deployZone?
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
    effects = []
    # get next door, depending on image num
    switch door.imageNum%8
      when 2
        to = x:door.x+1, y:door.y
      when 3
        to = x:door.x-1, y:door.y
      when 6
        to = x:door.x, y:door.y-1
      when 7
        to = x:door.x, y:door.y+1
        
    selectItemWithin actor.map.id, door, to, (err, doors) =>
      return callback err if err?
      # opens all doors
      for door in doors when door?.type?.id is 'door'
        effects.push [door, _.pick door, 'id', 'closed', 'imageNum']
        door.closed = false
        door.imageNum -= 2
        door.transition = 'open'
        @saved.push door
      # no more door to open (normally)
      console.log "#{actor.name or actor.kind} (#{actor.squad.name}) opens door at #{door.x}:#{door.y}"
      actor.doorToOpen = null
      detectBlips actor, @, effects, (err) =>
        return callback err if err?
        addAction 'open', actor, effects, @, callback
      
module.exports = new OpenRule()