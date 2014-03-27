_ = require 'underscore'
async = require 'async'
Item = require 'hyperion/model/Item'
Ratio = require './ratio'
{selectItemWithin, mergeChanges, distance} = require './common'
{wallPositions, doorPositions, alienCapacities, moveCapacities} = require './constants'
  
# Anything related to visibility:
# - tiles on line
# - is tile visible from another
# - blip revealing
# - wall positions
# - next wall/door on line
# - is tile reachable/targetable from character
module.exports = {

  # Returns walls position inside a given rectangle
  # Position are casted down into horizontal and vertical : 
  # horizontal[0][2] indicates a wall between the two first columns (y=0), at thrid row (x=2)
  # vertical[1][0] indicates a wall between rows 2 and 3 (x=1), at first column (y=0)
  #
  # @param from [Object] from position, one of the rectangle corner
  # @param to [Object] to position, the other corner
  # @param items [Array<Item>] all items that lies inside the rectangle. 
  # *Caution*: do not include items without position, or with position not inside the rectangle
  # @param withCharacters [Boolean] Takes in account living characters when checking visibility. Default to false
  # @return a details object with:
  # @option return low [Object] x and y coordinates of rectangle lower left corner
  # @option return verticals [Array<Array<Boolean>>] vertical walls matrix
  # @option return horizontals [Array<Array<Boolean>>] horizontal walls matrix
  getWalls: (from, to, items, withCharacters = false) ->
    walls =
      minX: Math.min from.x, to.x 
      minY: Math.min from.y, to.y
      maxX: Math.max from.x, to.x
      maxY: Math.max from.y, to.y
      vertical: [] 
      horizontal: []
      
    numH = Math.abs from.y-to.y
    numV = Math.abs from.x-to.x
    # compute walls within the selected rectangle
    for i in [0...numH]
      walls.horizontal.push (false for j in [0..numV])
    for j in [0...numV]
      walls.vertical.push (false for i in [0..numH])
      
    # search walls and occupant at start position
    for item in items 
      if walls.minX <= item?.x <= walls.maxX and walls.minY <= item?.y <= walls.maxY
        pos = {}
        if item.type.id is 'wall'
          # single wall
          pos = wallPositions[item.imageNum] 
        else if item.type.id is 'door'
          # closed door
          pos = doorPositions[item.imageNum] if item.closed
        else if withCharacters and item.type.id in ['alien', 'marine'] and not item.dead and not(item.x is from.x and item.y is from.y) and !(item.x is to.x and item.y is to.y)
          # characters occupy whole tile
          pos = top: true, bottom: true, left: true, right: true
        # complete wall matrix
        if pos.left and item.x-walls.minX isnt 0 
          walls.vertical[item.x-walls.minX-1][item.y-walls.minY] = true
        if pos.right and item.x-walls.minX isnt numV
          walls.vertical[item.x-walls.minX][item.y-walls.minY] = true
        if pos.bottom and item.y-walls.minY isnt 0
          walls.horizontal[item.y-walls.minY-1][item.x-walls.minX] = true
        if pos.top and item.y-walls.minY isnt numH
          walls.horizontal[item.y-walls.minY][item.x-walls.minX] = true
    walls
    
  # Compute tiles crossed by a straight from from to to.
  #
  # @param from [Object] from position
  # @param to [Object] to position
  # @return an array of coordinates between those two positions
  tilesOnLine: (from, to) ->
    #console.log "\n--- visibility from #{from.x}|#{from.y} to #{to.x}|#{to.y}"
    # get straight equation
    a = new Ratio from.y - to.y, from.x - to.x
    vertical = from.x - to.x is 0
    b = new Ratio(to.y, 1).subtract a.multiply to.x
    negate = a.valueOf() < 0
    invert = false
    tiles= []
    if vertical
      # vertical straight
      tiles = (x:from.x, y:y for y in [from.y..to.y])
    else if -1 <= a.valueOf() <= 1
      # flat straight: goes on x, and start with lowest
      if (to.x < from.x)
        [from, to] = [to, from] 
        invert = true
      tiles = [{x:from.x, y:from.y}]
      threshold = if a.equals 0 then new Ratio 0 else new Ratio(1).subtract a.abs()
      #console.log "> flat a:#{a}, b:#{b}, threshold:#{threshold}, negate:#{negate}"
      for x in [from.x...to.x]
        if a.equals 0
          y = b
        else
          y = a.multiply(x+0.5).add(b).add 1,2
        fY = Math.floor y.valueOf()
        diff = y.subtract fY
        diff = new Ratio(1).subtract diff if negate and !diff.equals 0
        #console.log "> flat x:#{x}, y:#{y}, fY:#{fY}, diff:#{diff}, sup:#{diff.subtract(threshold).numerator() > 0}"
        tiles.push x:x+1, y:(if negate and diff.equals 0 then fY-1 else fY)
        tiles.push x:x+1, y:(if negate then fY-1 else fY+1) if diff.subtract(threshold).numerator() > 0 and x+1 isnt to.x
    else
      # steep straight: goes on y, and start with lowest
      if (to.y < from.y)
        [from, to] = [to, from] 
        invert = true
      tiles = [{x:from.x, y:from.y}]
      threshold = if a.equals 0 then new Ratio 0 else new Ratio(1).subtract a.reciprocal().abs()
      #console.log "> steep a:#{a}, b:#{b}, threshold:#{threshold}, negate:#{negate}"
      for y in [from.y...to.y]
        x = new Ratio(y+0.5).subtract(b).divide(a).add 1,2
        fX = Math.floor x.valueOf()
        diff = x.subtract fX
        diff = new Ratio(1).subtract diff if negate and !diff.equals 0
        #console.log "> steep x:#{x}, y:#{y}, fX:#{fX}, diff:#{diff}, sup:#{diff.subtract(threshold).numerator() > 0}"
        tiles.push x:(if negate and diff.equals 0 then fX-1 else fX), y:y+1
        tiles.push x:(if negate then fX-1 else fX+1), y:y+1 if diff.subtract(threshold).numerator() > 0 and y+1 isnt to.y
          
    tiles.reverse() if invert
    #console.log JSON.stringify tiles, null, 0
    tiles
    
  # Indicates weither or not an actor can see a given target
  # 
  # @param from [Object] x/y coordinates of the concerned actor
  # @param to [Object] x/y coordinates of the checked target
  # @param items [Array<Item>] array of items inside the rectangle containing both from and to coordinates
  # @param withCharacters [Boolean] Takes in account characters when checking visibility. Default to false
  # @return null if target is visible, coordinate of obstacle otherwise
  hasObstacle: (from, to, items, withCharacters = false) ->
    # dead characters are not visible :)
    return to if to.dead
    return null if from?.x is to?.x and from?.y is to?.y
    #console.log "--- \n hasObstacle #{from.x}|#{from.y} -> #{to.x}|#{to.y}"
    # get tiles on the line, and walls
    tiles = module.exports.tilesOnLine from, to
    walls = module.exports.getWalls from, to, items, withCharacters
    #console.log ">> walls:", JSON.stringify walls, null, 2
    # now quit if one wall is crossed
    for i in [0..tiles.length-2]
      current = tiles[i]
      next = tiles[i+1]
      #console.log ">> check x:#{current.x} y:#{current.y} and x:#{next.x} y:#{next.y}"
      if next.x is current.x
        # on the same row: check horizontals
        [current, next] = [next, current] if next.y < current.y
        if walls.horizontal[current.y-walls.minY][current.x-walls.minX]
          #console.log "horizontal wall in horz"
          return next
      else if next.y is current.y
        # on the same column: check verticals
        [current, next] = [next, current] if next.x < current.x
        if walls.vertical[current.x-walls.minX][current.y-walls.minY]
          #console.log "vertical wall in vert"
          return current
      else 
        # neither on same column not row: check vertical on two tiles
        [current, next] = [next, current] if next.x < current.x
        vBottom = walls.vertical[current.x-walls.minX][current.y-walls.minY]
        vTop = walls.vertical[current.x-walls.minX][next.y-walls.minY]
        if vBottom and vTop
          #console.log "vertical wall"
          return current
           
        # check horizontal on two tiles (order tiles on y)
        [current, next] = [next, current] if next.y < current.y
        hLeft = walls.horizontal[current.y-walls.minY][current.x-walls.minX]  
        hRight = walls.horizontal[current.y-walls.minY][next.x-walls.minX]
        if hLeft and hRight
          #console.log "horizontal wall"
          return next 
          
        # check also wall angles: positive slope
        if ((hLeft and vBottom) or (hRight and vTop)) and current.x < next.x
          #console.log "horizontal angle"
          return next 
        
        # and negatice slope
        if ((hLeft and vTop) or (hRight and vBottom)) and current.x > next.x
          #console.log "vertical angle"
          return current 
        
    # no walls: it's visible
    null
    
  # Reveals all blips visible by a given marine, or check if the actor blip revealed himself
  # If no actor is given, check all combinations
  #
  # @param actor [Item|String] concerned marine or blip. To check all blips, give a map id (string)
  # @param rule [Rule] caller rule, to save modified objects
  # @param effects [Array<Array>] for each modified model, an array with the modified object at first index
  # and an object containin modified attributes and their previous values at second index (must at least contain id).
  # @param callback [Function] end callback, invoked with 
  # @option callback error [Error] an error object, or null if no error occured
  detectBlips: (actor, rule, effects, callback) ->
    # early return if actor is an Item but not marine and already revealed
    if actor?.type? and actor.type.id isnt 'marine' and actor.revealed isnt false
      return callback null
    # select all items within map
    Item.where('map', actor?.map?.id or actor).exec (err, items) =>
      return callback err if err?
      # merge items with saved/removed object
      mergeChanges items, rule
      
      reveal = (blip, end) =>
        # store previous blip state
        effects.push [blip, _.pick blip, 'id', 'moves', 'rcNum', 'ccNum', 'imageNum', 'revealed', 'x', 'y']
        blip.revealed = true
        imageNum = alienCapacities[blip.kind].imageNum
        # for dreadnought, choose the right image depending on the equiped weapons
        if blip.kind is 'dreadnought'
          weapons = (weapon.id or weapon for weapon in blip.weapons[1..])
          console.log weapons.join '_'
          imageNum = imageNum[weapons.join '_']
        blip.imageNum = imageNum
        # subtract already done moves to possible moves (use first weapon to get infos)
        weapon = blip.weapons[0]?.id or blip.weapons[0]
        blip.moves = moveCapacities[weapon] - moveCapacities.blip + blip.moves
        blip.moves = 0 if blip.moves < 0
        blip.rcNum = 1
        blip.ccNum = 1
        parts = []
        # for dreadnought, creates parts
        if blip.kind is 'dreadnought'
        
          # get dreadnought nearest walls and doors
          blocks = (
            for item in items when (item.type.id is 'wall' or item.type.id is 'door' and item.closed) and 
                blip.x-1 <= item.x <= blip.x+1 and 
                blip.y-1 <= item.y <= blip.y+1
              item
          )
          # candidates position to reveal dreadnought
          candidates = [
            {x: blip.x, y: blip.y, moves: 0}
            {x: blip.x-1, y: blip.y, moves: 0}
            {x: blip.x, y: blip.y-1, moves: 0}
            {x: blip.x-1, y: blip.y-1, moves: 0}
          ]
          
          # check that no block is sharing position with dreadnought part
          for pos in candidates
            # if no block is on the same tile than a part
            if module.exports.isFreeForDreadnought blocks, pos, 'current'
              # update position and quit
              blip.x = pos.x
              blip.y = pos.y
              break
            # if no position is legal, we'll keep the same position.

         # now creates the dreadnought parts
          for i in [0..2]
            part = new Item
              type: blip.type
              kind: blip.kind
              revealed: true
              squad: blip.squad
              main: blip
              x: blip.x+(if i is 0 then 1 else i-1)
              y: blip.y+(if i is 0 then 0 else 1)
              map: blip.map
              imageNum: null
            rule.saved.push part
            parts.push part
            
        
        # add attack action
        blip.fetch (err, blip) =>
          return end err if err?
          blip.squad.actions++
          blip.parts = parts
          console.log "reveal blip #{blip.kind} at #{blip.x}:#{blip.y}"
          # TODO : pas de detection automatique de la modification des actions de l'escouade !!!!
          # on est obligé de le déclarer nous même
          rule.saved.push blip, blip.squad
          end null
        
      # for a marine, check all other blips visibility
      if actor?.type?.id is 'marine'
        return async.each items, (blip, next) =>
          if blip.type.id is 'alien' and !blip.revealed and not module.exports.hasObstacle(actor, blip, items)?
            return reveal blip, next
          next()
        , callback
      else if actor?.revealed is false
        # for an unrevealed blip, check if he revealed himself to other marines
        for marine in items when marine.type.id is 'marine' and not module.exports.hasObstacle(marine, actor, items)?
          return reveal actor, callback
        # not visible to anyone
        callback null
      else 
        # check all possible blips against all existing marines
        marines = []
        blips = []
        for candidate in items 
          marines.push candidate if candidate.type.id is 'marine'
          blips.push candidate if candidate.revealed is false
        async.each marines, (marine, endMarine) =>
          async.each blips, (blip, endBlip) =>
            if blip.revealed or module.exports.hasObstacle(marine, blip, items)?
              endBlip()
            else
              reveal blip, endBlip
          , endMarine
        , callback
      
  # Checks that a given position is free for a dreadnought to move on.
  # Can also check current position for blip revealing.
  #
  # @param items [Array<Model>] array containing items for the checked and dreadnought positions
  # @param actor [Model] current dreadnought, before move
  # @param direction [String] current, right, top, left or bottom direction in which the dreadnought is moving
  # @return true if dreadnought can move in this direction, false otherwise
  isFreeForDreadnought: (items, actor, direction) ->
    # depending on the direction, store position and their respective contitions that may prevent move
    conditions = {}
    switch direction
      when 'current'
        # to check current position, no wall in the inner crux, nor door
        conditions["#{actor.x}_#{actor.y}"] = walls: ['top', 'right'], doors: ['top', 'right']
        conditions["#{actor.x+1}_#{actor.y}"] = walls: ['top', 'left'], doors: ['top', 'left']
        conditions["#{actor.x}_#{actor.y+1}"] = walls: ['bottom', 'right'], doors: ['bottom', 'right']
        conditions["#{actor.x+1}_#{actor.y+1}"] = walls: ['bottom', 'left'], doors: ['bottom', 'left']
      when 'left'
        # on left neighbors, vertical walls/doors or items or horizontal wall in the middle
        conditions["#{actor.x-1}_#{actor.y}"] = walls: ['right', 'top'], doors: ['right'], character: true
        conditions["#{actor.x-1}_#{actor.y+1}"] = walls: ['right', 'bottom'], doors: ['right'], character: true
        # on same tiles, vertical walls/doors
        conditions["#{actor.x}_#{actor.y}"] = walls: ['left'], doors: ['left']
        conditions["#{actor.x}_#{actor.y+1}"] = walls: ['left'], doors: ['left']
      when 'right'
        # on right neighbors, vertical walls/dors or items or horizontal wall in the middle
        conditions["#{actor.x+2}_#{actor.y}"] = walls: ['left', 'top'], doors: ['left'], character: true
        conditions["#{actor.x+2}_#{actor.y+1}"] = walls: ['left', 'bottom'], doors: ['left'], character: true
        # on same tiles, vertical walls/doors
        conditions["#{actor.x+1}_#{actor.y}"] = walls: ['right'], doors: ['right']
        conditions["#{actor.x+1}_#{actor.y+1}"] = walls: ['right'], doors: ['right']
      when 'bottom'
        # on bottom neighbors, horizontal walls/doors or items or vertical wall in the middle
        conditions["#{actor.x}_#{actor.y-1}"] = walls: ['top', 'right'], doors: ['top'], character: true
        conditions["#{actor.x+1}_#{actor.y-1}"] = walls: ['top', 'left'], doors: ['top'], character: true
        # on same tiles, horizontal walls/doors
        conditions["#{actor.x}_#{actor.y}"] = walls: ['bottom'], doors: ['bottom']
        conditions["#{actor.x+1}_#{actor.y}"] = walls: ['bottom'], doors: ['bottom']
      when 'top'
        # on top neighbors, horizontal walls/doors or items or vertical wall in the middle
        conditions["#{actor.x}_#{actor.y+2}"] = walls: ['bottom', 'right'], doors: ['bottom'], character: true
        conditions["#{actor.x+1}_#{actor.y+2}"] = walls: ['bottom', 'left'], doors: ['bottom'], character: true
        # on same tiles, horizontal walls/doors
        conditions["#{actor.x}_#{actor.y+1}"] = walls: ['top'], doors: ['top']
        conditions["#{actor.x+1}_#{actor.y+1}"] = walls: ['top'], doors: ['top']
    for item in items
      prevent = conditions["#{item.x}_#{item.y}"]
      # item is at a position that may prevent move
      if prevent?
        switch item.type.id 
          when 'wall'
            # wall with matching side prevent moves
            return false for side in prevent.walls when wallPositions[item.imageNum][side]
          when 'door'
            # closed door prevent moves, open door cannot be the last move
            return false for side in prevent.doors when doorPositions[item.imageNum][side] or (side of doorPositions[item.imageNum] and actor.moves <= 1)
          when 'alien', 'marine'
            # undead alien or marine prevent move
            return false if prevent.character and not item.dead
    true
    
  # Checks that dreadnought is under a door or not
  #
  # @param items [Array<Model>] array containing map items at dreadnought and its parts positions
  # @param actor [Model] current dreadnought, before move
  # @return true if dreadnought is under an open door, false otherwise
  isDreadnoughtUnderDoor: (items, actor) ->
    # store position and their respective contitions that indicates an opened door above
    conditions = {}
    conditions["#{actor.x}_#{actor.y}"] = ['right', 'top']
    conditions["#{actor.x+1}_#{actor.y}"] = ['left', 'top']
    conditions["#{actor.x}_#{actor.y+1}"] = ['right', 'bottom']
    conditions["#{actor.x+1}_#{actor.y+1}"] = ['left', 'bottom']
    for item in items when item.type.id is 'door'
      doors = conditions["#{item.x}_#{item.y}"]
      if doors?
        # if the door has one of the expected side, returns true
        return true for side in doors when side of doorPositions[item.imageNum]
    false
    
  # Indicates wether a field is reachable from a given character, to move on it
  # If actor is revealed dreadnought, take care or selecting x+2,y+2 rectangle
  # 
  # @param actor [Item] concerned character
  # @param field [Field] tested field
  # @param items [Array<Item>] all existing items on the map in the actor/field rectangle
  # @return true if this field is reachable
  isReachable: (actor, field, items) ->
    # move possible if field is marine own base
    return false unless field?.mapId is actor?.map?.id and 
        actor.moves >= 1 and (field.typeId[0..5] isnt 'base-' or field.typeId is "base-#{actor.squad.name}")
        
    if actor.kind is 'dreadnought' and actor.revealed
      reachable = false
      # dreadnought moves 1 step vertically or horizontally, no diagonals
      switch field.x
        when actor.x-1, actor.x+2 
          # horizontal move
          return false unless field.y in [actor.y, actor.y+1]
          # check occupation on both horizontal lines, character not allowed
          return module.exports.isFreeForDreadnought items, actor, if field.x < actor.x then 'left' else 'right'
        when actor.x, actor.x+1 
          # vertical move
          return false unless field.y in [actor.y-1, actor.y+2]
          # check occupation on both vertical lines, character not allowed
          return module.exports.isFreeForDreadnought items, actor, if field.y < actor.y then 'bottom' else 'top'
      return false
    else
      # move possible if at distance 1 and no obstacle
      return false unless 1 is distance(actor, field) and module.exports.hasObstacle(actor, field, items) is null
      # check target occupant
      occupant = _.find items, (item) -> item.x is field.x and 
        item.y is field.y and 
        item.type.id in ['marine', 'alien'] and not item.dead
      # can share tile with a squadmate, only if enought move to exit
      return not occupant? or (actor.squad.id is (occupant.squad.id or occupant.squad) and actor.moves > 1)
  
  # Indicates wether a field/item target can be targeted with the given character weapon.
  # Common to range and close combat, thus you must check:
  # - weapon capabilities
  # - actor remaining attack
  # - target existence for close combat
  # Takes in account:
  # - target map and visibility
  # - flamer alignment specificity
  # Can be used asycnronously (without specifying items) or synchronously (by specifying items)
  #
  # @param actor [Item] concerned character
  # @param target [Field|Item] tested target field
  # @param weaponIdx [Number] index of selected weapon into the actor's weapons
  # @param itemsOrCallback [Array<Item>] items inside the rectangle defined by actor and target position. If a function, 
  # items are automatically retrieved, and the function invoked, with two arguments:
  # @option itemsOrCallback err [String] error string. Null if no error occured
  # @option itemsOrCallback from [Item] actor (or part for dreadnought) that can reach the target, null otherwise
  # @returns Only if callback is an array, returns the actor/part that can reach target, or null otherwise
  isTargetable: (actor, target, weaponIdx, itemsOrCallback) ->
    if _.isArray itemsOrCallback
      callback = (err, result) ->
        throw new err if err?
        result
    else
      callback = itemsOrCallback
      
    return callback null, null unless target? and actor?
    # deny unless on same map and targeting a field (mapId)
    return callback null, null unless actor.map?.id and (actor.map.id is target.mapId or actor.map.id is target.map?.id)
    
    proceed = (err, items) ->
      return callback err, null if err?
      # abort unless target visible to actor (character blocks visibility unless using flamer)
      candidates = [actor]
      # if actor is dreadnought, all part must be testes
      isDreadnought = actor.kind is 'dreadnought' and actor.revealed
      candidates = candidates.concat actor.parts if isDreadnought
        
      visible = false
      weapon = actor.weapons[weaponIdx]
      # for each candidate, stop at first position that has a visibility line
      for candidate in candidates when not module.exports.hasObstacle(candidate, target, items, weapon.id isnt 'flamer')?
        visible = true
        break
      
      return callback null, null unless visible
        
      # depending on the weapon
      switch weapon.id
        when 'flamer'
          # flamer allowed on horizontal, vertical or diagonal lines
          for candidate in candidates when candidate.x is target.x or candidate.y is target.y or Math.abs(candidate.x-target.x) is Math.abs candidate.y-target.y
            return callback null, candidate
          # no matching candidates
          return callback null, null
        when 'gloveSword', 'claws'
          # close combat only: check alignment and distance
          callback null, if 1 is distance(actor, target) and (target.x is actor.x or target.y is actor.y) then actor else null
        else
          callback null, actor
          
    # synchronous behaviour
    if _.isArray itemsOrCallback
      return proceed null, itemsOrCallback
    # asynchronous bejaviour now check visibility rules: get all items at actor and target coordinates
    selectItemWithin actor.map.id, actor, target, proceed
                    
  # Search for the nearest wall on the line (horizontal, vertical or diagonal)
  #
  # @param mapId [String] id of current map
  # @param from [Object] shooter position (x/y coordinates)
  # @param to [Object] target position (x/y coordinates)
  # @param callback [Function] end callback, invoked with:
  # @option callback err [Error] an error object or null if no error occured
  # @option callback wall [Object] the nearest wall position (x/y coordinates)
  # @option callback items [Array<Item>] loaded items between shooter and wall
  untilWall: (mapId, from, to, callback) ->
    # get map dimensions
    Item.findCached ["game-#{mapId.replace 'map-', ''}"], (err, [game]) =>
      return callback err if err? or !game?
      [unused, lowX, lowY, upX, upY] = game.mapDimensions.match /^(.*):(.*) (.*):(.*)$/
      [lowX, lowY, upX, upY] = [+lowX, +lowY, +upX, +upY]
      target = 
        x: to.x
        y: to.y
      # are we horinzontal or vertical ?
      vertical = from.x is to.x
      horizontal = from.y is to.y
      # range will be the distance until the nearest map edge
      range = 100000
      unless horizontal
        # vertical line or diagonal
        target.y = if from.y < to.y then upY else lowY
        range = Math.min range, Math.abs to.y-target.y
      unless vertical
        # horizontal line or diagonal
        target.x = if from.x < to.x then upX else lowX
        range = Math.min range, Math.abs to.x-target.x
      # select all items within actor position and nearest map edge
      selectItemWithin mapId, from, target, (err, items) =>
        return callback err if err?
        prev = null
        current = null
        for i in [1..range]
          # invert if both actor and to are above 0
          i = -i if from.x <= 0 and to.x < 0
          prev = current if current?
          current = 
            x: to.x
            y: to.y
          # goes on next tile
          unless horizontal
            current.y += if from.y < to.y then i else -i
          unless vertical
            current.x += if from.x < to.x then i else -i
          # stop if next tile isnt visible
          if module.exports.hasObstacle(from, current, items)?
            return callback null, prev or to, items
        # no wall found: reach max range
        callback null, current, items
        
  # Find within next items a door to open, and returns it
  #
  # @param positions [Model|Array<Model>] positions (with x and y coordinates) from which door may be opened
  # @param items [Array<Model>] array of items within 1 range from actor
  # @return a door to open, or null.
  findNextDoor: (positions, items) ->
    positions = [positions] unless _.isArray positions
    
    for pos in positions
      # search for closed door:
      for door in items when door.type.id is 'door' and door.closed
        # sharing same position, whatever the side
        return door if door.x is pos.x and door.y is pos.y
        # at left with right side
        return door if doorPositions[door.imageNum].right and door.x is pos.x-1 and door.y is pos.y
        # at right with left side
        return door if doorPositions[door.imageNum].left and door.x is pos.x+1 and door.y is pos.y
        # at bottom with top side
        return door if doorPositions[door.imageNum].top and door.x is pos.x and door.y is pos.y-1
        # at top with bottom side
        return door if doorPositions[door.imageNum].bottom and door.x is pos.x and door.y is pos.y+1
    return null

}