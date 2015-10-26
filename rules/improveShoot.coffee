Rule = require 'hyperion/model/Rule'
{useTwist, makeState} = require './common'

# "suicideAndroid", "mekaniakOrk" and "grenadierGretchin" twist rule: gives a selected alien an improved shoot
class ImproveShootRule extends Rule

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
    unless squad.isAlien and squad.waitTwist and squad.twist in ['suicideAndroid', 'mekaniakOrk', 'grenadierGretchin']
      return callback null, null 
      
    # select living revealed aliens with relevant kind
    switch squad.twist 
      when 'suicideAndroid' then kind = 'android'
      when 'mekaniakOrk' then kind = 'ork'
      else kind = 'gretchin'
    candidates = (member for member in squad.members when member.revealed and not member.dead and member.kind is kind )

    params = []
    if candidates.length > 0
      params.push
        name: 'target'
        type: 'object'
        within: candidates
    
    callback null, params

  # Keep twist on selected alien, to apply effect at turn end
  # For grenedier and makaniak, change the alien weapon
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

    # get target alien
    for member in squad.members when member.id is params.target
      target = member
      break
    
    console.log "applied twist #{twist} on #{target.id} (#{target.kind})"
    
    effects = [makeState target, 'weapons', 'twist']
    
    # double relevant actions depending on twist
    target.twist = twist
    switch twist
      when 'grenadierGretchin' then target.weapons = ['missileLauncher']
      when 'mekaniakOrk' then target.weapons = ['flamer']
  
    useTwist twist, game, squad, effects, @, callback

  
module.exports = new ImproveShootRule 'twists'