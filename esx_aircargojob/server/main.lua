ESX = nil

TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end) 

RegisterServerEvent('esx_fork:getPaid')
AddEventHandler('esx_fork:getPaid', function(amount)
	local xPlayer = ESX.GetPlayerFromId(source)	
	xPlayer.addMoney(math.floor(amount))	
end)


