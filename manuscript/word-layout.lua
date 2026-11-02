-- Keep comparison tables readable in Word and in subsequent R Markdown renders.
function Table(t)
  if #t.colspecs == 3 then
    local widths = {0.12, 0.26, 0.62}
    if pandoc.utils.stringify(t.head.rows[1].cells[1].contents):find('Period') then
      widths = {0.15, 0.44, 0.41}
    end
    for i, w in ipairs(widths) do t.colspecs[i][2] = w end
  end
  for _, row in ipairs(t.head.rows) do
    for _, cell in ipairs(row.cells) do
      for _, block in ipairs(cell.contents) do
        if block.content then
          block.content = {pandoc.Span(block.content, pandoc.Attr("", {}, {["custom-style"] = "Table Header"}))}
        end
      end
    end
  end
  return t
end

function Span(s)
  return s
end
