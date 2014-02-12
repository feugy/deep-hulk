_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
{selectItemWithin, addAction} = require './common'
{hasObstacle, findNextDoor} = require './visibility'

# Blip deployement rule. Only possible for alien
class DeployBlipRule extends Rule

  # Only applies for aliens that have possible deployement.
  # 
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameters (zone, x, y, and rank), or null/undefined if rule does not apply
  canExecute: (player, squad, context, callback) =>
    return callback null, null unless squad?.type?.id is 'squad' and squad?.isAlien and squad?.deployZone?
    callback null, [
      # deployement zone
      name:'zone'
      type:'string'
      within: squad.deployZone.split ','
    ,
      # x coordinate for deployement
      name: 'x'
      type: 'integer'
    ,
      # y coordinate for deployement
      name: 'y'
      type: 'integer'
    , 
      # deployed blip within squad members
      name: 'rank'
      type: 'integer'
      min: 0
      max: squad.members.length-1
    ]


  # Checks that the chosen coordinates are within the relevant zone, 
  # and that chosen blips is nor visible, not already deployed.
  # If so, deployed the blip.
  #
  # @param player [Player] the concerned player
  # @param squad [Item] the concerned squad
  # @param params [Object] associative array of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (player, squad, params, context, callback) =>
    # checks that blip is undeployed
    blip = squad.members[params.rank]
    return callback new Error "alreadyDeployed" if blip.revealed
    wasOnMap = blip.map?
    # action history
    effects = [
      [blip, _.pick blip, 'id', 'x', 'y', 'map', 'doorToOpen']
    ]
    
    # get deployable zone dimensions
    Item.findOne {map: squad.map.id, type:'deployable', zone:params.zone}, (err, deployable) =>
      return callback err or "no deployable zone #{params.zone} on map #{squad.map.id}" if err? or !deployable?
      [unused, lowX, lowY, upX, upY] = deployable.dimensions.match /^(.*):(.*) (.*):(.*)$/
      [lowX, lowY, upX, upY] = [+lowX, +lowY, +upX, +upY]
      # do not move one blip which is not already into the zone
      return callback new Error "alreadyDeployed" unless not blip.map? or lowX <= blip.x <= upX and lowY <= blip.y <= upY
      
      # checks that blips is inside the zone
      return callback new Error "notInZone" unless lowX <= params.x <= upX and lowY <= params.y <= upY
        
      # checks that blip will not be visible
      selectItemWithin squad.map.id, (err, items) =>
        return callback err if err?
        for item in items when item?.type?.id is 'marine'
          return callback new Error "positionVisible" unless hasObstacle(item, params, items)?
          
        # At last, deploy blip on map
        blip.map = squad.map
        blip.x = params.x
        blip.y = params.y
        
        # search for door to open
        blip.doorToOpen = findNextDoor params, items
        
        # add action for blip move
        squad.actions++ unless wasOnMap
        @saved.push blip
        addAction 'deploy', blip, effects, @, callback
  
module.exports = new DeployBlipRule 'blips'