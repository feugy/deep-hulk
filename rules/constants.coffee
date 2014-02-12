  
heavyWeapons = ["flamer", "autoCannon", "missileLauncher"]
commanderWeapons = ["heavyBolter", "gloveSword", "pistolAxe"]
marineWeapons = ["bolter"].concat heavyWeapons

# Common constants
module.exports = {
  
  # Maximum of games a player can create
  maxGames: 5
  
  # id of list game object that contains free games
  freeGamesId: 'freeGames'
  
  # images rank corresponding to squad ids
  squadImages: 
    alien: 0
    ultramarine: 1
    imperialfist: 2
    bloodangel: 3

  # heavy weapon ids for simple marines 
  heavyWeapons: heavyWeapons
  
  # weapon ids for commanders
  commanderWeapons: commanderWeapons
  
  # weapon ids for simple marines
  marineWeapons: marineWeapons

  # all possible marines and commanders weapon
  weapons: commanderWeapons.concat marineWeapons
  
  # walls position from their image index
  wallPositions: [
    {top: true}
    {right: true}
    {bottom: true}
    {left: true}
    {top: true, right: true}
    {top: true, left: true}
    {bottom: true, right: true}
    {bottom: true, left: true}
  ]
      
  # door position from their image index
  # **CAUTION** don't forget to update position when door ItemType images are modified !
  doorPositions: [
    {}
    {}
    {bottom: true}
    {bottom: true}
    {}
    {}
    {left: true}
    {left: true}
    {}
    {}
    {top: true}
    {top: true}
    {}
    {}
    {left: true}
    {left: true}
  ]
  
  # image indexes for a given weapon
  weaponImages: 
    ultramarine: {heavyBolter: 1, gloveSword: 2, pistolAxe: 0, bolter: 3, autoCannon: 4, flamer: 5, missileLauncher:6}
    imperialfist: {heavyBolter: 8, gloveSword: 9, pistolAxe: 7, bolter: 10, autoCannon: 11, flamer: 12, missileLauncher:13}
    bloodangel: {heavyBolter: 15, gloveSword: 16, pistolAxe: 14, bolter: 17, autoCannon: 18, flamer: 19, missileLauncher:20}

  # move capacities, depending on the equiped weapon
  moveCapacities:
    blip: 5
    bolter: 6
    gloveSword: 6
    pistolAxe: 6
    heavyBolter: 6
    autoCannon: 4
    missileLauncher: 4
    flamer: 4
    slugga: 8
    shoota: 6
	  assaultRifle: 4
	  claws: 8
    
  # store moves, armor and weapon capacities for aliens
  # use the same names as alien properties to allow quick copy during creation
  alienCapacities:
    gretchin:
      imageNum: 2
      armor: 0
      weapon: 'slugga'
      points: 2
    ork:
      imageNum: 1
      armor: 1
      weapon: 'shoota'
      points: 3
    chaosMarine:
      armor: 2
      weapon: 'bolter'
      points: 5
    chaosHeavyMarine:
      armor: 2
      weapon: 'missileLauncher'
      points: 10
    chaosCommander:
      armor: 2
      weapon: 'heavyBolter'
      points: 10
    android:
      armor: 2
      weapon: 'assaultRifle'
      points: 10
    genestealer:
      armor: 3
      weapon: 'claws'
      points: 0
  
}