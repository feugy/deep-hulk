_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
{selectItemWithin, makeState, useTwist, getDeployZone} = require './common'
{hasObstacle, findNextDoor} = require './visibility'

# "redeployment" twist rule: change location of at most three deployed blips
class RedeployRule extends Rule

  # Always appliable on alien squad if it has the relevant twist
  # 
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameters (zone, x, y, and rank), or null/undefined if rule does not apply
  canExecute: (player, squad, context, callback) =>
    # inhibit if waiting for deployment or other squad
    unless squad.isAlien and squad.waitTwist and squad.twist is 'redeployment'
      return callback null, null 
      
    candidates = (member for member in squad.members when member.map? and not member.revealed and not member.dead)

    params = []
    if candidates.length > 0
      # ask for a blip and its new coordinate
      params.push
        name: 'target'
        type: 'object'
        within: candidates
        numMax: 3
      , 
        name: 'x'
        type: 'integer'
        numMax: 3
      ,
        name: 'y'
        type: 'integer'
        numMax: 3
        
    callback null, params

  # For each blip, changes its position
  #
  # @param game [Item] the concerned game
  # @param squad [Item] the concerned alien squad
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (game, squad, params, context, callback) =>
    # check that we have enought coordinates
    return callback "missingCoordinates" unless params.target.length is params.x.length and params.x.length is params.y.length
    
    twist = squad.twist
    effects = []
    
    # no target found
    unless params.target.length > 0
      return useTwist twist, game, squad, effects, @, callback
    
    # get all map content to check visibility
    selectItemWithin squad.map.id, (err, items) =>
      return callback err if err?
      
      # get deployable zone
      getDeployZone game.mission.id, null, (err, zones) =>
        return callback err if err?
        tiles = []
        tiles.push x:x, y:y for y in [lowY..upY] for x in [lowX..upX] for part, {lowY, lowX, upY, upX} of zones

        for target, i in params.target
          x = params.x[i];
          y = params.y[i];
          
          # check that position is in regular field
          return callback new Error 'notInZone' unless _.findWhere(tiles, x:x, y:y)?
          
          # check that position isn't visible
          for item in items when item?.type?.id is 'marine'
            return callback new Error 'positionVisible' unless hasObstacle(item, {x:x, y:y}, items)?
               
          # get target alien
          for member in squad.members when member.id is target
            blip = member
            break
           
          # action history
          effects.push makeState blip, 'x', 'y', 'map', 'doorToOpen'
          console.log "applied twist #{twist} on #{blip.id}: move to #{x}:#{y}"
         
          # At last, move blip on map and refresh openable door
          blip.x = x
          blip.y = y
          blip.doorToOpen = findNextDoor blip, items
           
          # add action for blip move
          @saved.push blip
        
        # use twist and quit
        useTwist twist, game, squad, effects, @, callback
  
module.exports = new RedeployRule 'twists'