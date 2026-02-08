local utils = require("image/utils")

local has_magick = vim.fn.executable("magick") == 1
local has_convert = vim.fn.executable("convert") == 1
local has_identify = vim.fn.executable("identify") == 1

-- magick v6 + v7
local convert_cmd = has_magick and "magick" or "convert"

local function guard()
  if not (has_magick or has_convert) then
    error("image.nvim: ImageMagick CLI tools not found (need 'magick' or 'convert')")
  end
  if not has_identify and not has_magick then error("image.nvim: ImageMagick 'identify' command not found") end
end

---@class MagickCliProcessor: ImageProcessor
local MagickCliProcessor = {}

function MagickCliProcessor.get_format(path)
  local result = utils.magic.detect_format(path)
  if result then return result end
  -- fallback to slower method:
  guard()
  local result = nil
  local callback_error = nil
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local output = ""
  local error_output = ""

  vim.loop.spawn(has_magick and "magick" or "identify", {
    args = has_magick and { "identify", "-format", "%m", path } or { "-format", "%m", path },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then
      callback_error = error_output ~= "" and error_output or "Failed to get format"
    else
      result = output:lower():gsub("%s+$", "")
    end
  end)

  vim.loop.read_start(stdout, function(err, data)
    if err then return end
    if data then output = output .. data end
  end)

  vim.loop.read_start(stderr, function(err, data)
    if err then return end
    if data then error_output = error_output .. data end
  end)

  local success = vim.wait(5000, function()
    return result ~= nil or callback_error ~= nil
  end, 10)
  if callback_error then error(callback_error) end
  if not success then error("identify format detection timed out") end
  return result
end

function MagickCliProcessor.convert_to_png(path, output_path)
  guard()

  local actual_format = MagickCliProcessor.get_format(path)

  local out_path = output_path or path:gsub("%.[^.]+$", ".png")
  local done = false
  local callback_error = nil
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  -- for GIFs/PDFs convert the first frame/page
  if actual_format == "gif" or actual_format == "pdf" then path = path .. "[0]" end

  vim.loop.spawn(convert_cmd, {
    args = { path, "png:" .. out_path },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then
      callback_error = error_output ~= "" and error_output or "Failed to convert to PNG"
    else
      done = true
    end
  end)

  vim.loop.read_start(stderr, function(err, data)
    if err then return end
    if data then error_output = error_output .. data end
  end)

  local success = vim.wait(10000, function()
    return done or callback_error ~= nil
  end, 10)

  if callback_error then error(callback_error) end
  if not success then error("convert timed out") end

  return out_path
end

function MagickCliProcessor.get_dimensions(path)
  local result = utils.dimensions.get_dimensions(path)
  if result then return result end
  -- fallback to slower method:
  guard()

  local actual_format = MagickCliProcessor.get_format(path)

  local callback_error = nil
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local output = ""
  local error_output = ""

  -- GIF/PDF
  if actual_format == "gif" or actual_format == "pdf" then path = path .. "[0]" end

  vim.loop.spawn(has_magick and "magick" or "identify", {
    args = has_magick and { "identify", "-format", "%wx%h", path } or { "-format", "%wx%h", path },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then
      callback_error = error_output ~= "" and error_output or "Failed to get dimensions"
    else
      local width, height = output:match("(%d+)x(%d+)")
      result = { width = tonumber(width), height = tonumber(height) }
    end
  end)

  vim.loop.read_start(stdout, function(err, data)
    if err then return end
    if data then output = output .. data end
  end)

  vim.loop.read_start(stderr, function(err, data)
    if err then return end
    if data then error_output = error_output .. data end
  end)

  local success = vim.wait(5000, function()
    return result ~= nil or callback_error ~= nil
  end, 10)

  if callback_error then error(callback_error) end
  if not success then error("identify dimensions timed out") end

  return result
end

function MagickCliProcessor.resize(path, width, height, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-resized.%1")
  local done = false
  local callback_error = nil
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn(convert_cmd, {
    args = {
      path,
      "-scale",
      string.format("%dx%d", width, height),
      out_path,
    },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then
      callback_error = error_output ~= "" and error_output or "Failed to resize"
    else
      done = true
    end
  end)

  vim.loop.read_start(stderr, function(err, data)
    if err then return end
    if data then error_output = error_output .. data end
  end)

  local success = vim.wait(10000, function()
    return done or callback_error ~= nil
  end, 10)

  if callback_error then error(callback_error) end
  if not success then error("operation timed out") end

  return out_path
end

function MagickCliProcessor.crop(path, x, y, width, height, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-cropped.%1")
  local done = false
  local callback_error = nil
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn(convert_cmd, {
    args = {
      path,
      "-crop",
      string.format("%dx%d+%d+%d", width, height, x, y),
      out_path,
    },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then
      callback_error = error_output ~= "" and error_output or "Failed to crop"
    else
      done = true
    end
  end)

  vim.loop.read_start(stderr, function(err, data)
    if err then return end
    if data then error_output = error_output .. data end
  end)

  local success = vim.wait(10000, function()
    return done or callback_error ~= nil
  end, 10)

  if callback_error then error(callback_error) end
  if not success then error("operation timed out") end

  return out_path
end

function MagickCliProcessor.brightness(path, brightness, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-bright.%1")
  local done = false
  local callback_error = nil
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn(convert_cmd, {
    args = {
      path,
      "-modulate",
      tostring(brightness),
      out_path,
    },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then
      callback_error = error_output ~= "" and error_output or "Failed to adjust brightness"
    else
      done = true
    end
  end)

  vim.loop.read_start(stderr, function(err, data)
    if err then return end
    if data then error_output = error_output .. data end
  end)

  local success = vim.wait(10000, function()
    return done or callback_error ~= nil
  end, 10)

  if callback_error then error(callback_error) end
  if not success then error("operation timed out") end

  return out_path
end

function MagickCliProcessor.saturation(path, saturation, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-sat.%1")
  local done = false
  local callback_error = nil
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn(convert_cmd, {
    args = {
      path,
      "-modulate",
      string.format("100,%d", saturation),
      out_path,
    },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then
      callback_error = error_output ~= "" and error_output or "Failed to adjust saturation"
    else
      done = true
    end
  end)

  vim.loop.read_start(stderr, function(err, data)
    if err then return end
    if data then error_output = error_output .. data end
  end)

  local success = vim.wait(10000, function()
    return done or callback_error ~= nil
  end, 10)

  if callback_error then error(callback_error) end
  if not success then error("operation timed out") end

  return out_path
end

function MagickCliProcessor.hue(path, hue, output_path)
  guard()
  local out_path = output_path or path:gsub("%.([^.]+)$", "-hue.%1")
  local done = false
  local callback_error = nil
  local stdout = vim.loop.new_pipe()
  local stderr = vim.loop.new_pipe()
  local error_output = ""

  vim.loop.spawn(convert_cmd, {
    args = {
      path,
      "-modulate",
      string.format("100,100,%d", hue),
      out_path,
    },
    stdio = { nil, stdout, stderr },
    hide = true,
  }, function(code)
    if code ~= 0 then
      callback_error = error_output ~= "" and error_output or "Failed to adjust hue"
    else
      done = true
    end
  end)

  vim.loop.read_start(stderr, function(err, data)
    if err then return end
    if data then error_output = error_output .. data end
  end)

  local success = vim.wait(10000, function()
    return done or callback_error ~= nil
  end, 10)

  if callback_error then error(callback_error) end
  if not success then error("operation timed out") end

  return out_path
end

return MagickCliProcessor
