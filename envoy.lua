#!/usr/bin/lua
--
-- https://github.com/fabienroyer/enphase-envoy
-- Author: Fabien Royer
-- License: GPL v3.0
--
local function capture(cmd)
  local f = assert(io.popen(cmd, 'r'))
  local s = assert(f:read('*a'))
  f:close()
  return s
end

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function split(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t={}
  local i=1
  for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
    t[i] = str
    i = i + 1
  end
  return t
end

local function scrape(data, beginMarker, endMarker)
  local _, mark1Stop = string.find(data, beginMarker)
  local mark2Start, _ = string.find(data, endMarker)
  local payload = string.sub(data, mark1Stop + 1, mark2Start - 1)
  payload = string.gsub(payload, "<td>", "")
  payload = string.gsub(payload, "</td>", "")
  payload = string.gsub(payload, "<tr>", "")
  payload = string.gsub(payload, "</tr>", "")
  payload = string.gsub(payload, "\n", "")
  return split(trim(payload), " ")
end

local function toWatts(power, units)
  if units == "W" then
    return tonumber(power)
  elseif units == "kW" then
    return tonumber(power * 1000)
  elseif units == "mW" then
    return tonumber(power * 1000000)
  else
    error("Unknown power units!")
  end
end

local function post(site, influxdb, watts, invOnline, invCount)
  local t = {}
  t[#t+1] = string.format("watts,site=%s value=%s", site, tostring(watts))
  t[#t+1] = string.format("inverters,site=%s value=%s", site, tostring(invCount))
  t[#t+1] = string.format("online,site=%s value=%s", site, tostring(invOnline))
  local data = table.concat(t, "\n")
  local curlCmd = string.format("curl -s -i -XPOST \'http://%s/write?db=solar&precision=s\' --data-binary \'%s\'", influxdb, data)
  os.execute(curlCmd)
end

local function main(site, envoyGW, influxDB)
  local data = capture(string.format("curl -s \'http://%s/home?locale=en\'", envoyGW))
  if data ~= nil then
    local generation = scrape(data, "Currently generating", "Last connection to website")
    local invCount = scrape(data, "Number of Microinverters", "Number of Microinverters Online")
    local invOnline = scrape(data, "Number of Microinverters Online", "Current Software Version")
    local watts = toWatts(generation[1], generation[2])
    post(site, influxDB, watts, invOnline[1], invCount[1])
  end
end

-- Solar array location name
local site = "home"
-- Address of the Envoy gateway to scrape data from
local envoyGW = "10.0.0.123"
-- Address and port number of the InfluxDB instance where to log the data
local influxDB = "localhost:8086"

main(site, envoyGW, influxDB)
