function deepcopy(tbl)
	local t = {}
	for k,v in pairs(tbl) do
		if type(v) ~= "table" then 
			t[k] = v
		else
			t[k] = deepcopy(v)
		end
	end
	return t
end

function pick(tbl) -- Picks a random element from a table
	return tbl[math.random(1,#tbl)]
end

function explode(str,fmt) -- Explodes the string into an array, with words separated by $fmt
	fmt = fmt or " "
	local s = str
	local a = {}
	local f = s:find(" ")
	while f do -- Doing this with a for loop would be faster. Not sure how to do it though
		a[#a+1] = s:sub(1,f-1)
		s = s:sub(f+1)
		f = s:find(" ")
	end
	a[#a+1] = s -- Gets the last word of the string, or possibly the whole string if $fmt is not found anywhere
	return a
end

function newstate(c,m,s,i)
	local s = {
		civ  = (c or 1),
		mil  = (m or 0),
		infra = (i or 0),
		slots = (s or 8)
	}
	return s;
end

function newqueueobj(t,i)
	local q = {
		type = t,
		statenum = i,
		progress = 0
	}
	return q
end

function getcount(states,type)
	local m = 0
	for i=1,#states.states do
		if not states.states[i][type] then
			for k,v in pairs(states.states[i]) do
				print(k,v)
			end
			os.exit(0)
		end
		m = m + states.states[i][type]
	end
	return m
end

function getbonuses(states,type,day)
	if events[day] then
		local event_name = events[day]
		if eventfuncs[event_name] then
			eventfuncs[event_name](states)
		end
	end
	return states.bonuses[type];
end

function isnotqueued(states,j,type)
	for i=1,#states.queue do
		local queued = states.queue[i]
		if queued.statenum == j and queued.type == type then
			return false
		end
	end
	return true
end

function getbeststate(states,type)
	local best = {
		slots = -math.huge,
		infra = -math.huge
	};
	local num;
	for i=1,#states.states do
		local other = states.states[i]
		if isnotqueued(states,i,type) then
			if type == "infra" then
				if other.infra < 10 and other.infra > best.infra then
					best = other
					num = i
				end
			else
				if other.slots > 0 and other.civ + other.mil < other.slots then
					if other.infra > best.infra then
						best = other
						num = i
					end
				end
			end
		end
	end
	return num; -- May return nil if no state is found
end

thebest = {
	day = math.huge,
	civs = 0,
	mils = 0,
	infra =0,
	orders = "Fuck."
}

function finish(states,d,o)
	local c,m,i = getcount(states,"civ"),getcount(states,"mil"),getcount(states,"infra")
	if (c*1.5 + m + i*0.1)/d > (thebest.civs*1.5 + thebest.mils + thebest.infra*0.1) / thebest.day then
		thebest = {
			day = d,
			civs = c,
			mils = m,
			infra = i,
			orders = o
		}
		io.write("-----------\n")
		for k,v in pairs(thebest) do
			print(k,v)
		end
	end
end

costs = {
	civ = 10800,
	mil = 7200,
	infra = 3000
}


decisions = {
	function(states,day,orders) -- Swap to next stage
		local buildstage = states.buildstage
		if buildstage == "mil" then
			return
		end
		local newstates = deepcopy(states)
		if buildstage == "civ" then
			newstates.buildstage = "mil"
		else
			newstates.buildstage = "civ"
		end
		local beststadt = getbeststate(newstates,newstates.buildstage)
		if not beststadt then return end
		table.insert(newstates.queue,newqueueobj(newstates.buildstage,beststadt))
		findbest(newstates,day,orders .. newstates.buildstage .. ",")
	end,
	function(states,day,orders) -- build current type
		local beststadt = getbeststate(states,states.buildstage)
		if not beststadt then return end
		--[[
		if states.buildstage == "infra" then
			print("I tried infrastructure!")
		end
		--]]
		local newstates = deepcopy(states)
		table.insert(newstates.queue,newqueueobj(states.buildstage,beststadt))
		findbest(newstates,day,orders .. states.buildstage .. ",")
	end
}



function progress_tick(states,day)
	local cnt = getcount(states,"civ")
	local civsleft = math.floor(cnt - math.floor((cnt + getcount(states,"mil")) * states.toastercivs))
	for i,queued in ipairs(states.queue) do
		local usedcivs;
		if civsleft >= 15 then
			usedcivs = 15
			civsleft = civsleft - 15
		elseif civsleft > 0 then
			usedcivs = civsleft
			civsleft = 0
		else
			break
		end
		local builtstate = states.states[queued.statenum]
		local progress = queued.progress + getbonuses(states,queued.type,day) * usedcivs * 5 * (1 + builtstate.infra / 10)
		
		if progress > costs[queued.type] then -- If we're done
			--[[
			if not builtstate[queued.type] then
				for k,v in pairs(builtstate) do
					print(k,v)
					print(queued.type)
				end
				os.exit(0)
			end
			--]]
			builtstate[queued.type] = builtstate[queued.type] + 1
			table.remove(states.queue,i)
		else
			queued.progress = progress;
		end
	end
end

function findbest(states,day,orders)
	
	if #states.queue == 0 and not getbeststate(states,"mil") then -- If we're done
		finish(states,day,orders)
		return;
	end
	
	if #states.queue < getcount(states,"civ") / 15 then
		for k,action in pairs(decisions) do
			action(states,day,orders)
		end
	end
	
	repeat
		if day > tonumber(arg[1]) then
			finish(states,day,orders)
			return;
		end
		progress_tick(states,day)
		day = day + 1
	until #states.queue < getcount(states,"civ") / 15;
	
	for k,action in pairs(decisions) do
		action(states,day,orders)
	end
end

local startstates = {
	queue = {},
	states = {},
	buildstage = "infra",
	bonuses = {
		civ = 1,
		mil = 1,
		infra = 1
	},
	toastercivs = 0
}
local sf = io.open("D:\\Scripts\\Lua\\hoi4_industry_rollout\\Industry-Rollout-AI\\1936states.txt")
if sf then
	for line in sf:lines() do
		if line:sub(1,1) ~= "#" then
			local arr = explode(line)
			table.insert(startstates.states,newstate(tonumber(arr[1]),tonumber(arr[2]),tonumber(arr[3]),tonumber(arr[4])))
			--print(arr[1],arr[2],arr[3],arr[4])
			print("Loaded " .. arr[5] .. "...")
		end
	end
end
io.close(sf)

eventfuncs = {
--WAR ECONOMIES
	civilian = function(states)
		states.toastercivs = 0.35
		states.bonuses.civ = 0.7
		states.bonuses.mil = 0.7
	end,
	partial = function(states)
		states.toastercivs = 0.25
		states.bonuses.civ = 1
		states.bonuses.mil = 1.1
	end,
--MARKET POLICIES
	export = function(states)
		states.bonuses.civ = states.bonuses.civ + 0.1
		states.bonuses.mil = states.bonuses.mil + 0.1
		states.bonuses.infra = states.bonuses.infra + 0.1		
	end,
--FOCUS TREE SHIT
	newciv = function(states)
		local affstate = pick(states.states)
		affstate.civ = affstate.civ + 1
		affstate.slots = affstate.slots + 1
	end,
--TECH
	construction = function(states)
		states.bonuses.civ = states.bonuses.civ + 0.1
		states.bonuses.mil = states.bonuses.mil + 0.1
		states.bonuses.infra = states.bonuses.infra + 0.1
	end,
	industry = function(states)
		for i,state in pairs(states.states) do
			state.slots = math.floor(state.slots * 1.2)
		end
	end,
}
events = {}

local ef = io.open("D:\\Scripts\\Lua\\hoi4_industry_rollout\\Industry-Rollout-AI\\events.txt")
if ef then
	for line in ef:lines() do
		if line:sub(1,1) ~= "#" then
			local arr = explode(line)
			events[tonumber(arr[1])] = arr[2]
			--print(arr[1],arr[2],arr[3],arr[4])
			print("Loaded " .. arr[2] .. "...")
		end
	end
end
io.close(ef)

if #startstates.states == 0 then
	for i=1,6 do
		startstates.states[i] = newstate()
	end
end

findbest(startstates,0,"")










