_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
Item = require 'hyperion/model/Item'
ClientConf = require 'hyperion/model/ClientConf'
{useTwist, makeState} = require './common'
{moveCapacities, heavyWeapons, weaponImages} = require './constants'

# "depletedMunitions" and "jammedWeapon" twist rule: for selected marine, replace its heavy weapon by a bolter, or disable for a turn.
class ProblematicWeaponRule extends Rule

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
    unless squad.isAlien and squad.waitTwist and squad.twist in ['depletedMunitions', 'jammedWeapon']
      return callback null, null 
      
    # select living marines on the map
    Item.where('map', squad.map.id).where('type', 'marine')
        .where('dead', false).exec (err, marines) =>
      return callback err if err?
      params = []
        
      # only keeps marines with heavy weapons
      candidates = _.filter marines, (marine) ->
        (marine.weapons[0]?.id or marine.weapons[0]) in heavyWeapons
        
      if candidates.length > 0
        params.push
          name: 'target'
          type: 'object'
          within: candidates
      return callback null, params

  # Replace the weapon by a bolter, and apply available equipments
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
    
    # get labels
    ClientConf.findCached ['default'], (err, [conf]) =>
      return callback err if err?
      
      # fetch marine target and its squad
      Item.findCached [params.target], (err, [target]) =>
        err = new Error "No marine with id #{params.target}" if not err? and not target?
        return callback err if err?
        Item.findCached [target.squad], (err, [targetSquad]) =>
          return callback err if err?
        
          Item.fetch [target, targetSquad], (err, [target, targetSquad]) =>
            return callback err if err?
            
            concerned = target.weapons[0]?.id or target.weapons[0]
            console.log "applied twist #{twist} on #{target.name} (#{targetSquad.name}): #{concerned}"
            
            if twist is 'jammedWeapon'
              # just set range combat num to 0 to disable
              effects = [makeState target, 'rcNum']
              target.rcNum = 0
              return useTwist twist, game, targetSquad, [], @, true, {weapon: conf.values.labels[concerned]}, callback
              
            # enrich history action added by shoot to add twist information
            effects = [makeState target, 'imageNum', 'moves', 'weapons', 'equipment']
            target.moves = moveCapacities.bolter
            target.weapons = ['bolter']
            target.imageNum = weaponImages[targetSquad.name].bolter
            
            # update equipments: removes suspensors and add pistol bolters or assault blades, but keep targeter
            if 'suspensors' in target.equipment
              target.equipment.splice target.equipment.indexOf('suspensors'), 1
              
            other = _.find targetSquad.members, (marine) -> marine.id isnt target.id and marine.weapons[0] is 'bolter'
            target.equipment.push 'assaultBlades' if 'assaultBlades' in other.equipment
            target.equipment.push 'pistolBolters' if 'pistolBolters' in other.equipment
              
            # send event concerning target squad, plus removed weapon name
            useTwist twist, game, targetSquad, effects, @, true, {weapon: conf.values.labels[concerned]}, callback
  
module.exports = new ProblematicWeaponRule 'twists'