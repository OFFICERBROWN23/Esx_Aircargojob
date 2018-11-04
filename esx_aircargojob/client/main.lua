
ESX = nil
				
Citizen.CreateThread(function()
	while ESX == nil do
		TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
		Citizen.Wait(1)
	end
end)

local playerData = {}	
local onDuty = false	  
local isInMarker = false  
local menuIsOpen = false  
local taskPoints = {}	  
local forkBlips = {}       
local currentZone = 'none'
local Blips = {}		   
local packetsDelivered = 0 
local currentJob = 'none'  
local currentBox = nil	  
local lastDelivery = -1   
local lastPickup = -2   
local zOffset = -0.65	
local hintToDisplay = "no hint to display"				
local displayHint = false								
local currentVehicle = nil											
local currentPlate = ''												


function elementAt(tab, indx)
  local count = 0
  local ret = nil
  for k, v in pairs(tab) do
    count = count + 1
	if count == indx then
	ret = v
	break
	end
  end
  return ret
end

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(xPlayer)		
    playerData = xPlayer							
    refreshBlips()									
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
  playerData.job = job						
  onDuty = false							
  deleteBlips()								
  refreshBlips()						
end)

Citizen.CreateThread(function()
	if Config.enableVehDamageProtection then
		while true do
			if onDuty and IsPedInAnyVehicle(GetPlayerPed(-1)) and isMyCar() then
				local vehicle = GetVehiclePedIsIn(GetPlayerPed(-1), false)
				if GetVehicleEngineHealth(vehicle) <= 800 then
					SetEntityHealth(vehicle, 1000)
					SetVehicleEngineHealth(vehicle, 1000)
					SetVehicleEngineOn(vehicle, true, true)
				end
			end
			Citizen.Wait(1000)
		end
	end
end)

function drawBlip(coords, icon, text)
  local blip = AddBlipForCoord(coords.x, coords.y, coords.z)	
  SetBlipSprite (blip, icon)		
  SetBlipDisplay(blip, 4)			
  SetBlipScale  (blip, 0.9)			
  SetBlipColour (blip, 81)			
  SetBlipAsShortRange(blip, true)	
	
  BeginTextCommandSetBlipName("STRING")	
  AddTextComponentString(text)		
  EndTextCommandSetBlipName(blip)	
  table.insert(forkBlips, blip)	   
end

function refreshBlips()
	if playerData.job.name ~= nil and playerData.job.name == 'Heli' then 	
		drawBlip(Config.locker, 370, "Put Work Clothing On")			 	
		drawBlip(Config.carSpawner, 481, "Spawn Cargo Heli")					
		drawBlip(Config.carDelete, 481, "Despawn Cargo Heli")				
	end
end

function deleteBlips()
  if forkBlips[1] ~= nil then 	
    for i = 1, #forkBlips, 1 do	
      RemoveBlip(forkBlips[i])	
      forkBlips[i] = nil		
    end
  end
end

Citizen.CreateThread(function()
  while true do										
    Citizen.Wait(1)
    if displayHint then							
      SetTextComponentFormat("STRING")				
      AddTextComponentString(hintToDisplay)			
      DisplayHelpTextFromStringLabel(0, 0, 1, -1)	
    end
  end
end)

function displayMarker(coords)
	DrawMarker(0, coords.x, coords.y, coords.z + 0.75, 0.0, 0.0, 0.0, 0, 0.0, 0.0, 1.0, 1.0, 1.0, 15, 15, 255, 100, false, true, 2, false, false, false, false) 
end

function isMyCar()
	return currentPlate == GetVehicleNumberPlateText(GetVehiclePedIsIn(GetPlayerPed(-1), false))
end

function spawnFork()							
	local vehicleModel = GetHashKey('uh1calfire')	
	RequestModel(vehicleModel)				
	while not HasModelLoaded(vehicleModel) do	
		Citizen.Wait(0)
	end
	currentCar = CreateVehicle(vehicleModel, Config.carSpawnPoint.x, Config.carSpawnPoint.y, Config.carSpawnPoint.z, Config.carSpawnPoint.h, true, false)
	SetVehicleHasBeenOwnedByPlayer(currentCar,  true)														
	SetEntityAsMissionEntity(currentCar,  true,  true)														
	SetVehicleNumberPlateText(currentCar, "BEEP" .. math.random(1000, 9999))								
	local id = NetworkGetNetworkIdFromEntity(currentCar)													
	SetNetworkIdCanMigrate(id, true)																																																
	TaskWarpPedIntoVehicle(GetPlayerPed(-1), currentCar, -1)											
	local props = {																							
		modEngine       = 1,
		modTransmission = 1,
		modSuspension   = 1,
		modTurbo        = true,																				
	}
	ESX.Game.SetVehicleProperties(currentCar, props)
	Wait(1000)																							
	currentPlate = GetVehicleNumberPlateText(GetVehiclePedIsIn(GetPlayerPed(-1), false))
end

function trackBox()
	Citizen.CreateThread(function()
		while currentJob == 'pickup' do
			Citizen.Wait(5)
			if currentBox ~= nil and DoesEntityExist(currentBox) then
				local coords = GetEntityCoords(currentBox)
				local playerCoords = GetEntityCoords(GetPlayerPed(-1))
				setGPS(coords)	
				if playerIsInside(playerCoords, coords, 4) then
					goDeliver()
				end
				if playerIsInside(playerCoords, coords, 100) then
					local temp = {x = coords.x, y = coords.y, z = coords.z + Config.boxZ}
					displayMarker(temp)
				end
			end
		end
	end)
end

function spawnBox(coords)
	Citizen.CreateThread(function()
		repeat
			Citizen.Wait(500)
		until boxCanSpawn(taskPoints['deliver'])
		
		ESX.Game.SpawnObject('prop_boxpile_07d', {
			x = coords.x,
			y = coords.y,
			z = coords.z
		}, function(obj)
			SetEntityHeading(obj, coords.h)
			PlaceObjectOnGroundProperly(obj)
			currentBox = obj
		end)
	end)
end

function deleteBox()
	if currentBox ~= nil and DoesEntityExist(currentBox) then
		DeleteEntity(currentBox)
		return true
	end
	return false
end

function deleteCurrentBox()
	if currentBox ~= nil and DoesEntityExist(currentBox) then
		DeleteEntity(currentBox)
	end
end

function giveWork()
	local indA = 0
	local indB = 0
	repeat 
		indA = math.random(1, #Config.objPoints)	
	until indA ~= lastPickup
	local temp = Config.objPoints[indA]
	taskPoints['pickup'] = { x = temp.x, y = temp.y, z = temp.z, h = temp.h}
	repeat
		indB = math.random(1, #Config.objPoints)
	until indB ~= indA and indB ~= lastDelivery and isFar(taskPoints['pickup'], Config.objPoints[indB], Config.minDistance)
	local temp2 = Config.objPoints[indB]
	taskPoints['deliver'] = { x = temp2.x, y = temp2.y, z = temp2.z, h = temp2.h}
	lastPickup = indA
	lastDelivery = indB
end

function boxIsInside(coords)
	if currentBox ~= nil and DoesEntityExist(currentBox) then
        local objCoords = GetEntityCoords(currentBox)
        local distance  = GetDistanceBetweenCoords(coords.x,  coords.y,  coords.z,  objCoords.x,  objCoords.y,  objCoords.z,  true)
		return distance < 1.25
	else
		return false
	end
end

function boxCanSpawn(coords)
	local object = GetClosestObjectOfType(coords.x,  coords.y,  coords.z,  3.0,  GetHashKey('prop_boxpile_07d'), false, false, false)
	if DoesEntityExist(object) then
        local objCoords = GetEntityCoords(object)
        local distance  = GetDistanceBetweenCoords(coords.x,  coords.y,  coords.z,  objCoords.x,  objCoords.y,  objCoords.z,  true)
		return distance > 5.0
	else
		return true
	end
end


function goDeliver()
	ESX.ShowNotification('~y~Deliver the cargo to the marked location~y~')
	setGPS(taskPoints['deliver'])
	currentJob = 'deliver'
end

function goPickup()
	ESX.ShowNotification('~y~Pickup cargo from location~y~')
	setGPS(taskPoints['pickup'])
	currentJob = 'pickup'
	trackBox()
	spawnBox(taskPoints['pickup'])
end

function nextJob()
	packetsDelivered = packetsDelivered + 1
	giveWork()
	goPickup()
end

function startWork()
	packetsDelivered = 0
	spawnFork()
	giveWork()
	goPickup()
end

function deleteCar()
	local entity = GetVehiclePedIsIn(GetPlayerPed(-1), false)	
	ESX.Game.DeleteVehicle(entity)							
end

function getPaid()
	setGPS(0)													
	if IsPedInAnyVehicle(GetPlayerPed(-1)) and isMyCar() then			
		deleteCar()												
		local pay = packetsDelivered * Config.pay
		TriggerServerEvent('esx_fork:getPaid', pay)
		ESX.ShowNotification('~w~Payment: ~g~ +' .. pay .. ' ~w~$.')
	else														
		ESX.ShowNotification('~r~Wheres the Cargo Heli?')
		local pay = math.floor(packetsDelivered * (Config.pay * 0.6))			
		if packetsDelivered < 2 then						
			pay = 0								
		end
		TriggerServerEvent('esx_fork:getPaid', pay)
		ESX.ShowNotification('~w~Payment: ~r~ +' .. amount .. ' ~w~$.')
	end
	currentJob = 'none'											
	currentPlate = ''												
	currentVehicle = nil											
	packetsDelivered = 0											
	taskPoints = {}													
	deleteCurrentBox()												
end

function isFar(coords1, coords2, distance) 
	local vecDiffrence = GetDistanceBetweenCoords(coords1.x, coords1.y, coords1.z, coords2.x, coords2.y, coords2.z, false)
	return vecDiffrence > distance			
end

function setGPS(coords)
	if Blips['fork'] ~= nil then 	
		RemoveBlip(Blips['fork'])	
		Blips['fork'] = nil			
	end
	if coords ~= 0 then
		Blips['fork'] = AddBlipForCoord(coords.x, coords.y, coords.z)		
		SetBlipRoute(Blips['buzz'], true)								
	end
end

function playerIsInside(playerCoords, coords, distance) 	
	local vecDiffrence = GetDistanceBetweenCoords(playerCoords, coords.x, coords.y, coords.z, false)
	return vecDiffrence < distance		
end

function taskTrigger(zone)				
	if zone == 'locker' then				
		openMenu()
	elseif zone == 'start' then				
		startWork()
	elseif zone == 'pay' then	
		getPaid()
	end
end

Citizen.CreateThread(function()
	while true do																
		Citizen.Wait(50)
		if playerData.job ~= nil and playerData.job.name == "Heli" and onDuty then
			local playerCoords = GetEntityCoords(GetPlayerPed(-1))
			if currentJob == 'deliver' and taskPoints['deliver'] ~= nil and playerIsInside(playerCoords, taskPoints['deliver'], 5.5) and boxIsInside(taskPoints['deliver']) then
				if deleteBox() then
					nextJob()
				end
			end
		end
	end
end)

Citizen.CreateThread(function()
	while true do																
		Citizen.Wait(2)					
		if not menuIsOpen then
			local playerCoords = GetEntityCoords(GetPlayerPed(-1))
			if playerData.job ~= nil and playerData.job.name == "Heli" and playerIsInside(playerCoords, Config.locker, 2.5) then 				
				isInMarker = true
				displayHint = true																
				hintToDisplay = "Press E to Change into clothing"									
				currentZone = 'locker'																
			elseif onDuty and taskPoints['deliver'] == nil and playerIsInside(playerCoords, Config.carSpawner, 2.5) then	
				isInMarker = true
				displayHint = true
				hintToDisplay = "Press E to start job"
				currentZone = 'start'
			elseif onDuty and currentJob == 'deliver' and taskPoints['deliver'] ~= nil and playerIsInside(playerCoords, taskPoints['deliver'], Config.pickupDistance) then
				isInMarker = true
				displayHint = true
				hintToDisplay = "~y~Move the Cargo to the marked position DO NOT DROP!~y~"
				currentZone = 'none' 
			elseif playerData.job ~= nil and playerData.job.name == "Heli" and currentPlate ~= '' and playerIsInside(playerCoords, Config.carDelete, 1.5) then  				
				isInMarker = true
				displayHint = true
				hintToDisplay = "Press E to return the aircraft"
				currentZone = 'pay'
			else																			
				isInMarker = false
				displayHint = false
				hintToDisplay = "No hint to display"
				currentZone = 'none'
			end
			if IsControlJustReleased(0, 38) and isInMarker then
				taskTrigger(currentZone)													
				Citizen.Wait(500)
			end
		end
	end
end)

Citizen.CreateThread(function()
	while true do																			
		Citizen.Wait(1)
		local playerCoords = GetEntityCoords(GetPlayerPed(-1))
		if playerData.job ~= nil and playerData.job.name == "Heli" and playerIsInside(playerCoords, Config.locker, 100) then 
			displayMarker(Config.locker)
		end
		if onDuty and currentJob == 'none' and playerIsInside(playerCoords, Config.carSpawner, 100) then			
			displayMarker(Config.carSpawner)
		end
		if onDuty and currentJob == 'deliver' and playerIsInside(playerCoords, taskPoints['deliver'], 100) then 			
			displayMarker(taskPoints['deliver'])
		end
		if playerData.job ~= nil and playerData.job.name == "Heli" and onDuty and currentPlate ~= '' and playerIsInside(playerCoords, Config.carDelete, 100) then  		
			displayMarker(Config.carDelete)
		end																			
	end
end)

function openMenu()									
  menuIsOpen = true
  ESX.UI.Menu.CloseAll()										
  ESX.UI.Menu.Open(
    'default', GetCurrentResourceName(), 'locker',			
    {
      title    = "Locker",							
      elements = {
        {label = "Work Clothing", value = 'fork_wear'},		
        {label = "Normal Clothing", value = 'everyday_wear'}	
      }
    },
    function(data, menu)									
      if data.current.value == 'everyday_wear' then			
        onDuty = false										
        ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin)	
            TriggerEvent('skinchanger:loadSkin', skin)						
        end)
      end
      if data.current.value == 'fork_wear' then
        onDuty = true
        ESX.TriggerServerCallback('esx_skin:getPlayerSkin', function(skin, jobSkin)
          if skin.sex == 0 then
              TriggerEvent('skinchanger:loadClothes', skin, jobSkin.skin_male)
          else
              TriggerEvent('skinchanger:loadClothes', skin, jobSkin.skin_female)
          end
        end)
      end
      menu.close()
	  menuIsOpen = false
    end,
    function(data, menu)
      menu.close()
	  menuIsOpen = false
    end
  )
end

