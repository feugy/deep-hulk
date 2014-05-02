_ = require 'underscore'
Rule = require 'hyperion/model/Rule'
{addAction} = require './common'

# Use some equipment during the game
class UseEquipmentRule extends Rule

  # Only applies on squad and one of its marine.
  # Ask for a possible equipment within squad available equipments
  # 
  # @param actor [Item] the concerned squad
  # @param marine [Item] the concerned marine
  # @param context [Object] extra information on resolution context
  # @param callback [Function] called when the rule is applied, with two arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback params [Array] array of awaited parameter (may be empty), or null/undefined if rule does not apply
  canExecute: (squad, marine, context, callback) =>
    # inhibit if waiting for deployment or other squad
    unless squad?.type?.id is 'squad' and marine?.type?.id is 'marine' and marine in squad.members and squad.equipment?.length > 0
      return callback null, null 
    callback null, [
      name: 'equipment'
      type: 'string'
      within: squad.equipment
    ]

  # Equip the selected equipment on choosen marine, if it make sense.
  # Equipment is removed from squad's inventory
  #
  # @param actor [Item] the concerned actor
  # @param target [Item] the concerned target
  # @param params [Object] associative array of awaited parametes: equipment choosen.
  # @param context [Object] extra information on execution context
  # @param callback [Function] called when the rule is applied, with one arguments:
  # @option callback err [String] error string. Null if no error occured
  # @option callback result [Object] an arbitrary result of this rule.
  execute: (squad, marine, {equipment}, context, callback) =>
    effects = [[squad, revealBlips: squad.revealBlips, equipment: squad.equipment.concat()]]
    
    switch equipment
      when 'meltaBomb' 
        # melta bomb will be used on next assault
        effects.push [marine, equipment: marine.equipment.concat()]
        marine.equipment.push equipment
        message = 'meltaBombEquiped'
      when 'mediKit' 
        # medi kit is applied immediately
        commander = _.findWhere squad.members, isCommander:true
        if not commander.dead
          effects.push [commander, _.pick commander, 'life']
          commander.life = 6
          message = 'commanderHealed'
        else
          message = 'commanderAlreadyDead'
      when 'blindingGrenade'
        # marines cannot be targeted during the turn
        marine.immune = true for marine in squad.members
        message = 'marinesImmune'
      when 'detector'
        # decrement blips reveal counter if necessary
        squad.revealBlips-- if squad.revealBlips > 0
        
    # removes from inventory
    squad.equipment.splice squad.equipment.indexOf(equipment), 1 unless equipment is 'detector'
    
    addAction 'equip', squad, effects, @, (err) =>
      callback err, message
  
module.exports = new UseEquipmentRule()