function Initialize()
  taskFile = SKIN:GetVariable('TaskFile')
  slots = tonumber(SKIN:GetVariable('Slots', '15'))   -- number of row meters in the .ini
  maxTasks = slots
  emptyText = SKIN:GetVariable('EmptyText', 'No open tasks')
  -- Section: only read checkboxes under this markdown heading (e.g. "### Tasks"). Blank = whole file.
  section = SKIN:GetVariable('Section', '')
  section = section:gsub('^%s+', ''):gsub('%s+$', ''):lower()
  dueMarker = '\240\159\147\133' -- the due-date marker, parsed into "(due Mon DD)"
  markers = {
    dueMarker,          -- due
    '\226\143\179',     -- scheduled
    '\240\159\155\171', -- start
    '\226\156\133',     -- done
    '\226\157\140',     -- cancelled
    '\240\159\148\129', -- recurring
    '\226\158\149',     -- created
    '\226\143\171',     -- priority highest
    '\226\143\172',     -- priority lowest
    '\240\159\148\188', -- priority high
    '\240\159\148\189', -- priority low
    '\240\159\148\186', -- priority highest (alt)
    '\240\159\148\187', -- priority lowest (alt)
  }
  months = {'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'}
  tasks = {}  -- rebuilt each Update: { {text=..., raw=...}, ... } in row order
end

-- Pull "📅 YYYY-MM-DD" out of a task line and return ASCII "Mon DD" (e.g. "Jun 13"), or nil.
function dueOf(s)
  local _, m, d = s:match(dueMarker .. '%s*(%d%d%d%d)%-(%d%d)%-(%d%d)')
  if d then
    local mon = months[tonumber(m)] or m
    return mon .. ' ' .. tonumber(d)
  end
  return nil
end

-- Cut a task at the first metadata marker, leaving just the description. Trim trailing space.
function stripMeta(s)
  local cut = nil
  for _, mk in ipairs(markers) do
    local i = s:find(mk, 1, true)  -- plain text search, not a pattern
    if i and (cut == nil or i < cut) then cut = i end
  end
  if cut then s = s:sub(1, cut - 1) end
  return (s:gsub('%s+$', ''))
end

function Update()
  tasks = {}
  note = nil
  if not taskFile or taskFile == 'CONFIGURE' then
    note = 'Set TaskFile in the .ini'
  else
    local f = io.open(taskFile, 'r')
    if not f then
      note = 'Cannot open file (check TaskFile)'
    else
      local lineNo, inFront, current = 0, false, ''
      for line in f:lines() do
        lineNo = lineNo + 1
        line = line:gsub('^\239\187\191', '')             -- strip UTF-8 BOM
        local fence = line:match('^%s*%-%-%-%s*$') ~= nil  -- a '---' line
        local skip = false
        if lineNo == 1 and fence then
          inFront = true                                  -- frontmatter only if file opens with ---
          skip = true
        elseif inFront then
          skip = true
          if fence then inFront = false end               -- closing fence
        end
        if not skip then
          local heading = line:match('^#+%s+(.+)')
          if heading then
            current = heading:gsub('%s+$', ''):lower()    -- entered a new section
          else
            local task = line:match('^%s*[-*] %[ %] (.+)')
            if task and (section == '' or current == section) then
              local due = dueOf(task)
              local text = stripMeta(task)
              if text ~= '' and #tasks < maxTasks then
                local entry = '[ ]  ' .. text             -- ASCII checkbox, renders reliably
                if due then entry = entry .. '   (due ' .. due .. ')' end
                tasks[#tasks + 1] = {text = entry, raw = line}
              end
            end
          end
        end
      end
      f:close()
    end
  end
  render()
  return #tasks
end

-- Push current task text into the static row meters (once per update, NOT per redraw).
-- Visible rows get a real gap; unused rows collapse (Y=0R, hidden) so the last visible
-- row's true bottom is what the background sizes against — correct at any DPI / wrap.
function render()
  local n = #tasks
  for i = 1, slots do
    local meter = 'MeterTask' .. i
    if i <= n then
      SKIN:Bang('!SetOption', meter, 'Text', tasks[i].text)
      SKIN:Bang('!SetOption', meter, 'Y', (i == 1) and '#GapTop#R' or '#Gap#R')
    elseif i == 1 and n == 0 then
      SKIN:Bang('!SetOption', meter, 'Text', note or emptyText)
      SKIN:Bang('!SetOption', meter, 'Y', '#GapTop#R')
    else
      -- unused rows: empty text (height 0, no clickable area) collapsed onto the last
      -- visible row (Y=0R) so the background measures the true content bottom.
      SKIN:Bang('!SetOption', meter, 'Text', '')
      SKIN:Bang('!SetOption', meter, 'Y', '0R')
    end
  end
  SKIN:Bang('!UpdateMeter', '*')  -- recompute layout, then resize the background to fit
  SKIN:Bang('!Redraw')
end

-- Check off row n: flip its "- [ ]" to "- [x]" in the file, byte-preserving everything else.
function toggle(n)
  n = tonumber(n)
  local t = tasks[n]
  if not t then return end
  local f = io.open(taskFile, 'rb')
  if not f then return end
  local data = f:read('*a')
  f:close()
  local s, e = data:find(t.raw, 1, true)  -- locate the exact original line
  if not s then return end
  local repl = t.raw:gsub('%[ %]', '[x]', 1)  -- flip only the first checkbox on that line
  data = data:sub(1, s - 1) .. repl .. data:sub(e + 1)
  local w = io.open(taskFile, 'wb')
  if not w then return end
  w:write(data)
  w:close()
end
