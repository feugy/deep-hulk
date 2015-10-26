async = require 'async'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
{useTwist, makeState} = require './common'
{isDreadnoughtUnderDoor, isFreeForDreadnought, findNextDoor} = require './visibility'

# "alienTeleporter" twist rule: move selected alien or blips
class AlienTeleporterRule extends Rule

  # Always appliable on alien squad if it has the relevant twist
  # 
  # @param game [Item] the concerned game
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (game, squad, context, callback) =>
    # inhibit if waiting for deployment or other squad
    unless squad.isAlien and squad.waitTwist and squad.twist is 'alienTeleporter'
      return callback null, null 
      
    candidates = (member for member in squad.members when member.revealed and not member.dead)

    params = []
    if candidates.length >= 2
      params.push
        name: 'target'
        type: 'object'
        numMin: 2
        numMax: 2
        within: candidates
    
    callback null, params

  # for alienTeleporter, inverse selected alien positions, taking parts in account
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (game, squad, params, context, callback) =>
    twist = squad.twist
    # no target found
    unless params.target?
      return useTwist twist, game, squad, [], @, callback
      
    # get target aliens
    targets = (member for member in squad.members when member.id in params.target)
    console.log "applied twist #{twist} on #{targets[0].id} (#{targets[0].kind}) and #{targets[1].id} (#{targets[1].kind})"
    
    effects = [makeState(targets[0], 'x', 'y', 'doorToOpen'), makeState targets[1], 'x', 'y', 'doorToOpen']
    
    # invert values
    tmp = {}
    for prop in ['x', 'y', 'doorToOpen']
      tmp[prop] = targets[0][prop]
      targets[0][prop] = targets[1][prop]
      targets[1][prop] = tmp[prop]
      
    # dreadnought is special
    unless targets[0].kind is 'dreadnought' or targets[1].kind is 'dreadnought'
      return useTwist twist, game, squad, effects, @, callback
    
    # get all doors and walls
    Item.where('map', squad.map.id).where('type').in(['door', 'wall']).exec (err, blocks) =>
      return callback err if err?
      doors = (block for block in blocks when block.type.id is 'door')
      closed = (door for door in doors when door.closed)
      
      async.each targets, (target, next) =>
        return next() unless target.kind is 'dreadnought'
        # fetch to get parts
        target.fetch (err, target) =>
          return next err if err?
          
          # get legal position for dreadnought
          candidates = [
            {x: target.x, y: target.y, moves: 0}
            {x: target.x-1, y: target.y, moves: 0}
            {x: target.x, y: target.y-1, moves: 0}
            {x: target.x-1, y: target.y-1, moves: 0}
          ]
          for pos in candidates when isFreeForDreadnought blocks, pos, 'current', true
            target.x = pos.x
            target.y = pos.y
            break
            
          # update parts
          positions = [x: target.x, y: target.y]
          # updates also dreadnought parts
          for i in [0..2]
            target.parts[i].x = target.x+(if i is 0 then 1 else i-1)
            target.parts[i].y = target.y+(if i is 0 then 0 else 1)
            positions.push x: target.parts[i].x, y: target.parts[i].y
            
          # update 'under door' and 'door to open'
          target.doorToOpen = findNextDoor positions, closed
          target.underDoor = isDreadnoughtUnderDoor doors, target 
          @saved.push target
          next()
      , (err) =>
        return callback err if err?
        useTwist twist, game, squad, effects, @, callback
  
module.exports = new AlienTeleporterRule 'twists'