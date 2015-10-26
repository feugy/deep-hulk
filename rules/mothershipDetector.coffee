async = require 'async'
Item = require 'hyperion/model/Item'
Rule = require 'hyperion/model/Rule'
{useTwist, selectItemWithin} = require './common'
{revealBlip} = require './visibility'

# "MothershipDetector" twist rule: all blips are revealed
class MothershipDetectorRule extends Rule

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
    unless squad.isAlien and squad.waitTwist and squad.twist is 'mothershipDetector'
      return callback null, null 
    callback null, []

  # Reveals all blips on map
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
    console.log "applied twist #{twist}"
      
    # get all walls and doors
    selectItemWithin squad.map.id, (err, walls) =>
      return callback err if err?
      
      # evaluate blips
      blips = (member for member in squad.members when member.map? and not member.revealed)
      effects = []
      # reveal each of them
      async.each blips, (blip, next) =>
        console.log "#{blip.kind} (#{squad.name}) affected by #{twist}"
        revealBlip blip, walls, effects, @, next
      , (err) =>
        return callback err if err?
        # make history action
        useTwist twist, game, squad, effects, @, callback
  
module.exports = new MothershipDetectorRule 'twists'