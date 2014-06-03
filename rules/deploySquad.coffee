_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Map = require 'hyperion/model/Map'
Field = require 'hyperion/model/Field'
Item = require 'hyperion/model/Item'
{selectItemWithin} = require './common'
{findNextDoor} = require './visibility'
  
# Squad deployement: goes on map
class DeploySquadRule extends Rule

  # Player can deploy their squad if not already deployed.
  # 
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (actor, target, context, callback) =>
    if actor?._className is 'Player' and target?.type?.id is 'squad' and !(target?.map?)
      # check that target belongs to player
      return callback null, [] for squad in actor.characters when squad.id is target.id
    # otherwise, disallow
    callback null, null

  # Squad deployement modifies the deployement status
  #
  # @param actor [Item] the concerned actor
  # @param squad [Item] the concerned target
  # @param params [Object] associative array (may be empty) of awaited parametes, specified by resolve.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  execute: (actor, squad, params, context, callback) =>
    # affect Squad to relevant map
    id = squad.id.replace('squad-', '').replace /-\d*$/, ''
    Map.findCached ["map-#{id}"], (err, [map]) =>
      return callback err if err?
      squad.map = map
      squad.turnEnded = false
      # alien are not deployed at starts
      if squad.name is 'alien'
        squad.trap.map = map
        return callback null 
      # set all marine into their base
      Field.find {mapId: "map-#{id}", typeId:"base-#{squad.name}"}, (err, tiles) =>
        return callback err if err?
        # get surrounding walls and doors
        xs = _.pluck tiles, 'x'
        ys = _.pluck tiles, 'y'
        selectItemWithin map.id, {x:_.min(xs)-1, y:_.min(ys)-1}, {x:_.max(xs)+1, y:_.max(ys)+1}, (err, items) =>
          return callback err if err?
          # arbitrary affect marines to base tiles.
          for member, i in squad.members
            # checks that dreadnought have been configured !
            if squad.isAlien and not squad.configured and member.kind is 'dreadnought'
              return callback "needConfiguration"
            member.map = map
            member.x = tiles[i].x
            member.y = tiles[i].y
            # check also openable doors
            member.doorToOpen = findNextDoor member, items
          callback null
  
module.exports = new DeploySquadRule 'init'