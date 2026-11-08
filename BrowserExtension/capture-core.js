/* Pure geometry shared by the capture worker and regression checks. */
(function (root) {
  'use strict';
  const MAX_PIXELS = 40000000;
  const MAX_DIMENSION = 32768;
  const MAX_TILES = 80;
  function positive(value, name) { if (!Number.isFinite(value) || value <= 0) throw new Error(`Invalid ${name}.`); return value; }
  function axis(total, viewport) {
    positive(total, 'page size'); positive(viewport, 'viewport');
    const positions = [];
    for (let covered = 0; covered < total - 0.01;) {
      const scroll = Math.min(covered, Math.max(0, total - viewport));
      const end = Math.min(total, scroll + viewport);
      positions.push({scroll, start: covered, end});
      if (end <= covered) throw new Error('The page cannot be scrolled further.');
      covered = end;
      if (positions.length > MAX_TILES) throw new Error('Page is too long. Capture a selected area instead.');
    }
    return positions;
  }
  function plan(width, height, viewportWidth, viewportHeight) {
    const columns = axis(width, viewportWidth), rows = axis(height, viewportHeight);
    if (columns.length * rows.length > MAX_TILES) throw new Error('Page needs too many captures. Use a selected area instead.');
    const tiles = [];
    for (const row of rows) for (const column of columns) tiles.push({x: column.scroll, y: row.scroll, left: column.start, top: row.start, right: column.end, bottom: row.end});
    return {width, height, viewportWidth, viewportHeight, tiles};
  }
  function dimensions(width, height, scaleX, scaleY) {
    [width, height, scaleX, scaleY].forEach(v => positive(v, 'capture dimensions'));
    const pixels = {width: Math.round(width * scaleX), height: Math.round(height * scaleY)};
    if (!pixels.width || !pixels.height || pixels.width > MAX_DIMENSION || pixels.height > MAX_DIMENSION || pixels.width * pixels.height > MAX_PIXELS) throw new Error('Capture exceeds 40 million pixels. Choose 1× full-page resolution or a smaller selected area.');
    return pixels;
  }
  function placement(tile, actualX, actualY, scaleX, scaleY, outputScaleX = scaleX, outputScaleY = scaleY) {
    const dx = Math.round(tile.left * outputScaleX), dy = Math.round(tile.top * outputScaleY);
    const right = Math.round(tile.right * outputScaleX), bottom = Math.round(tile.bottom * outputScaleY);
    const sx = Math.round(tile.left * scaleX) - Math.round(actualX * scaleX), sy = Math.round(tile.top * scaleY) - Math.round(actualY * scaleY);
    const sw = Math.round(tile.right * scaleX) - Math.round(tile.left * scaleX), sh = Math.round(tile.bottom * scaleY) - Math.round(tile.top * scaleY);
    if (sx < -1 || sy < -1 || right <= dx || bottom <= dy) throw new Error('Page moved while capturing. Please try again.');
    return {sx: Math.max(0, sx), sy: Math.max(0, sy), width: right - dx, height: bottom - dy, sw, sh, dx, dy};
  }
  function region(rect, viewport, pixelWidth, pixelHeight) {
    const scaleX = pixelWidth / positive(viewport.width, 'viewport'), scaleY = pixelHeight / positive(viewport.height, 'viewport');
    const left = Math.max(0, Math.min(viewport.width, rect.x)), top = Math.max(0, Math.min(viewport.height, rect.y));
    const right = Math.max(left, Math.min(viewport.width, rect.x + rect.width)), bottom = Math.max(top, Math.min(viewport.height, rect.y + rect.height));
    const result = {x: Math.round(left * scaleX), y: Math.round(top * scaleY), width: Math.round(right * scaleX) - Math.round(left * scaleX), height: Math.round(bottom * scaleY) - Math.round(top * scaleY)};
    if (result.width < 2 || result.height < 2) throw new Error('Select a larger area.');
    dimensions(result.width, result.height, 1, 1);
    return result;
  }
  root.SnapCaptureCore = {MAX_PIXELS, MAX_DIMENSION, MAX_TILES, axis, plan, dimensions, placement, region};
  if (typeof module !== 'undefined') module.exports = root.SnapCaptureCore;
})(globalThis);
