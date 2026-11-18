
extends RefCounted

const HEROES = [

	# ORIGINAL 10 HEROES

	{"id":"aurelia","name":"Aurelia","class":"Warrior","rarity":2,"hp":150,"atk":25,"def":30,"spd":12},
	{"id":"kael","name":"Kael","class":"Mage","rarity":3,"hp":90,"atk":45,"def":12,"spd":18},
	{"id":"sylva","name":"Sylva","class":"Archer","rarity":2,"hp":110,"atk":30,"def":20,"spd":25},
	{"id":"draven","name":"Draven","class":"Warrior","rarity":4,"hp":200,"atk":55,"def":40,"spd":10},
	{"id":"nyra","name":"Nyra","class":"Assassin","rarity":5,"hp":120,"atk":75,"def":20,"spd":40},
	{"id":"orion","name":"Orion","class":"Mage","rarity":2,"hp":95,"atk":30,"def":15,"spd":18},
	{"id":"lyra","name":"Lyra","class":"Healer","rarity":3,"hp":130,"atk":20,"def":35,"spd":20},
	{"id":"ragnar","name":"Ragnar","class":"Tank","rarity":4,"hp":250,"atk":35,"def":60,"spd":8},
	{"id":"vex","name":"Vex","class":"Assassin","rarity":1,"hp":85,"atk":28,"def":12,"spd":26},
	{"id":"seraphina","name":"Seraphina","class":"Healer","rarity":5,"hp":160,"atk":50,"def":35,"spd":24},

	# 30 NEW ONE-STAR HEROES

	{"id":"brutus","name":"Brutus","class":"Warrior","rarity":1,"hp":95,"atk":18,"def":21,"spd":11},
	{"id":"aldric","name":"Aldric","class":"Warrior","rarity":1,"hp":90,"atk":20,"def":19,"spd":13},
	{"id":"toren","name":"Toren","class":"Warrior","rarity":1,"hp":105,"atk":17,"def":23,"spd":10},
	{"id":"cedric","name":"Cedric","class":"Warrior","rarity":1,"hp":88,"atk":21,"def":18,"spd":14},
	{"id":"garron","name":"Garron","class":"Warrior","rarity":1,"hp":100,"atk":19,"def":22,"spd":12},

	{"id":"elric","name":"Elric","class":"Mage","rarity":1,"hp":65,"atk":28,"def":9,"spd":17},
	{"id":"zephyr","name":"Zephyr","class":"Mage","rarity":1,"hp":62,"atk":30,"def":8,"spd":19},
	{"id":"merek","name":"Merek","class":"Mage","rarity":1,"hp":70,"atk":26,"def":11,"spd":16},
	{"id":"isolde","name":"Isolde","class":"Mage","rarity":1,"hp":66,"atk":29,"def":10,"spd":18},
	{"id":"theron","name":"Theron","class":"Mage","rarity":1,"hp":72,"atk":27,"def":12,"spd":15},

	{"id":"faye","name":"Faye","class":"Archer","rarity":1,"hp":72,"atk":22,"def":13,"spd":22},
	{"id":"rowan","name":"Rowan","class":"Archer","rarity":1,"hp":78,"atk":21,"def":14,"spd":20},
	{"id":"eryn","name":"Eryn","class":"Archer","rarity":1,"hp":68,"atk":24,"def":11,"spd":23},
	{"id":"caelum","name":"Caelum","class":"Archer","rarity":1,"hp":75,"atk":23,"def":12,"spd":21},
	{"id":"liora","name":"Liora","class":"Archer","rarity":1,"hp":70,"atk":22,"def":15,"spd":24},

	{"id":"kairo","name":"Kairo","class":"Assassin","rarity":1,"hp":62,"atk":25,"def":9,"spd":27},
	{"id":"zane","name":"Zane","class":"Assassin","rarity":1,"hp":60,"atk":27,"def":8,"spd":28},
	{"id":"riven","name":"Riven","class":"Assassin","rarity":1,"hp":66,"atk":24,"def":10,"spd":25},
	{"id":"sable","name":"Sable","class":"Assassin","rarity":1,"hp":58,"atk":26,"def":8,"spd":29},
	{"id":"dusk","name":"Dusk","class":"Assassin","rarity":1,"hp":64,"atk":28,"def":9,"spd":26},

	{"id":"elara","name":"Elara","class":"Healer","rarity":1,"hp":82,"atk":14,"def":19,"spd":17},
	{"id":"mira","name":"Mira","class":"Healer","rarity":1,"hp":85,"atk":13,"def":20,"spd":18},
	{"id":"solene","name":"Solene","class":"Healer","rarity":1,"hp":78,"atk":15,"def":18,"spd":19},
	{"id":"aveline","name":"Aveline","class":"Healer","rarity":1,"hp":88,"atk":12,"def":21,"spd":16},
	{"id":"nessa","name":"Nessa","class":"Healer","rarity":1,"hp":80,"atk":14,"def":22,"spd":18},

	{"id":"borin","name":"Borin","class":"Tank","rarity":1,"hp":125,"atk":17,"def":28,"spd":8},
	{"id":"thrain","name":"Thrain","class":"Tank","rarity":1,"hp":135,"atk":16,"def":30,"spd":7},
	{"id":"doran","name":"Doran","class":"Tank","rarity":1,"hp":118,"atk":18,"def":26,"spd":9},
	{"id":"haldor","name":"Haldor","class":"Tank","rarity":1,"hp":130,"atk":15,"def":31,"spd":8},
	{"id":"orgrim","name":"Orgrim","class":"Tank","rarity":1,"hp":140,"atk":17,"def":29,"spd":7},

	# 5 SIX-STAR HEROES

	{"id":"valtherion","name":"Valtherion","class":"Warrior","rarity":6,"hp":420,"atk":105,"def":110,"spd":22},
	{"id":"eclipsa","name":"Eclipsa","class":"Mage","rarity":6,"hp":230,"atk":180,"def":48,"spd":65},
	{"id":"kaizora","name":"Kaizora","class":"Assassin","rarity":6,"hp":280,"atk":165,"def":55,"spd":95},
	{"id":"sylphira","name":"Sylphira","class":"Healer","rarity":6,"hp":350,"atk":85,"def":100,"spd":60},
	{"id":"dreadmoor","name":"Dreadmoor","class":"Tank","rarity":6,"hp":600,"atk":75,"def":165,"spd":18},

	# 2 SEVEN-STAR HEROES

	{"id":"aetherion","name":"Aetherion","class":"Warrior","rarity":7,"hp":750,"atk":190,"def":175,"spd":55},
	{"id":"nyxara","name":"Nyxara","class":"Mage","rarity":7,"hp":480,"atk":260,"def":95,"spd":110}
]


static func get_heroes():
	return HEROES.duplicate(true)


static func get_heroes_by_rarity(rarity):
	var result = []

	for hero in HEROES:
		if hero["rarity"] == rarity:
			result.append(hero)

	return result
