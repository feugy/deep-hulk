async = require 'async'

# Update winner squad and game state for main or secondary mission.
# Innefective if corresponding mission is kind is not defined.
#
# @param squad [Item] winning squad
# @param rule [Rule] executing rule, to save squad
# @param isMain [Boolean] default to true, distinguish main and secondary mission
winMission = (squad, rule, isMain=true) =>
  prefix = if isMain then 'main' else 'secondary'
  # only if mission exists
  if squad.mission["#{prefix}Kind"]?
    squad.game["#{prefix}Completed"] = true
    squad.game["#{prefix}Winner"] = squad.name
    squad.points += if isMain then 30 else 15
    rule.saved.push squad
   
# Elimination missions are fullfilled on attack actions
# 
# @param squad [Item] concerned squad
# @param action [String] performed action that determine how to interpret details
# @param details [Object|Array] performed rule details (specific to rule)
# @param isMain [Boolean] distinguish main and secondary mission
# @param rule [Rule] rule from which the mission is checked
# @param callback [Function] end callback, invoked with: 
# @option callback err [Error] an Error object, or null it no error occurs
checkElimination = (squad, action, details, isMain, rule, callback) ->
  # elimination can be completed if rule is assault or shoot
  # details is an array of objects containing properties target and result
  return callback null unless action is 'attack'
  expectation = squad.mission["#{if isMain then 'main' else 'secondary'}Expectation"]
  return callback null unless expectation?
  # target is specified in mission.details
  for {target, result} in details 
    if target.kind is expectation.kind and result.dead
      # target eliminated !
      console.log "#{squad.name} has completed main mission by killing #{target.kind}"
      winMission squad, rule, isMain
      break
  callback null

# HighScore missions are fullfilled on end action only by highest marine or 
# 
# @param squad [Item] concerned squad
# @param action [String] performed action that determine how to interpret details
# @param details [Object|Array] performed rule details (specific to rule)
# @param isMain [Boolean] distinguish main and secondary mission
# @param rule [Rule] rule from which the mission is checked
# @param callback [Function] end callback, invoked with: 
# @option callback g [Error] an Error object, or null it no error occurs
checkHighScore = (squad, action, details, isMain, rule, callback) ->
  # highScore is determined at end. No details needed
  return callback null unless action is 'end'
  return squad.game.fetch (err, game) ->
    return callback err if err?
    max = -Infinity
    winner = null
    # get squad members
    async.map game.squads, (candidate, next) =>
      candidate.fetch next
    , (err, squads) =>
      # only living marines can win highscore
      for candidate in squads when candidate.points > max and not candidate.isAlien
        if _.any(candidate.members, (member) -> not member.dead)
          max = candidate.points
          winner = candidate
      return callback null unless winner?
      # and the mission is always won
      console.log "#{winner.name} has completed main mission by highscore #{max}"
      winMission winner, rule, isMain
      callback null
      
# Mission utilities
module.exports = {
  
  # Check if a given squad has completed main or secondary mission.
  # Invoked when an action has been performed. Supported actions are:
  # - attack: elimination/destruction missions can be completed
  # - move: race missions can be completed
  # - endOfGame: highScore/mostKills/leastLosses missions can be completed
  #
  # @param squad [Item] concerned squad
  # @param action [String] performed action that determine how to interpret details
  # @param rule [Rule] rule from which the mission is checked
  # @param details [Object|Array] performed rule details (specific to rule)
  # @param callback [Function] end callback, invoked with: 
  # @option callback err [Error] an Error object, or null it no error occurs
  checkMission: (squad, action, details, rule, callback) ->
    # get mission details
    squad.fetch (err, squad) ->
      return callback err if err
    
      process = (isMain, next) ->
        prefix = if isMain then 'main' else 'secondary'
        # realy quit if already complete or not specified
        return next null if squad.game["#{prefix}Completed"] or not squad.mission["#{prefix}Kind"]?
        switch squad.mission["#{prefix}Kind"]
          when 'elimination' then checkElimination squad, action, details, isMain, rule, next
          when 'highScore' then checkHighScore squad, action, details, isMain, rule, next
          
      # first check main mission
      process true, (err) ->
        return callback err if err?
        # then check secondary mission
        process false, (err) ->
          return callback err if err?
          # specific case: at end of game, uncompleted mission goes to alien
          return callback null unless action is 'end'
          squad.game.fetch (err, game) ->
            for other in game.squads when other.isAlien
              unless game.mainCompleted
                console.log "#{squad.name} has completed main mission be default !"
                winMission other, rule, true
              
              # secondary mission are optionnal
              if squad.mission.secondaryKind? and not game.secondaryCompleted
                console.log "#{squad.name} has completed secondary mission be default !"
                winMission other, rule, false
              return callback null
}