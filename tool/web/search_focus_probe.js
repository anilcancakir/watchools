// Types into the search field one key at a time and reads the field back
// between keys.
//
// This exists because it is the only gate that can see the bug it was written
// for, and two that should have caught it could not.
//
// A widget test cannot. `Şimdi` and `Vitrin` used to move the search field into
// a different parent when a query stopped matching, which destroyed `WInput`'s
// state; the workaround that carried the `FocusNode` across the move made a
// widget test asserting `hasFocus` pass while the browser still dropped every
// key, because a widget test never touches the real engine and the keyboard on
// web arrives through a hidden DOM input the framework opens on a focus
// transition.
//
// The dusk walk cannot either. `fill_search` in `tool/dusk/_lib.sh` re-resolves
// the ref on every call and writes the whole string in one `dusk:fill`, so it
// never types a second character against a field whose parent has just swapped:
// `fill_search 'zzzzzz'` in `lineup_e2e.sh` passed straight through the bug a
// user reported.
//
// Usage, against a build that carries enough data for a query to find nothing:
//
//   flutter build web --profile --dart-define=WATCHOOLS_SCALE=5000
//   (cd build/web && python3 -m http.server 8088 --bind 127.0.0.1) &
//   playwright-cli open --browser=chrome http://127.0.0.1:8088
//   playwright-cli --raw run-code --filename=tool/web/search_focus_probe.js
//
// Expected on both views, for `z q x v` then two backspaces:
//
//   z -> 'z'   q -> 'zq'   x -> 'zqx'   v -> 'zqxv'   ⌫ -> 'zqx'   ⌫ -> 'zq'
//
// A view that stops accumulating at `q` is the regression: `q` is the keystroke
// that empties the 5000 channel line-up.
//
// The click coordinates assume 1440x900 and the toolbar's first line. They are
// the one brittle part; a layout change moves them.
async (page) => {
  await page.setViewportSize({ width: 1440, height: 900 });

  const value = () =>
    page.evaluate(() => {
      const el = document.querySelector('input');
      return el ? el.value : '(no input in the dom)';
    });

  const run = async (label) => {
    const steps = [];
    await page.mouse.click(320, 46);
    await page.waitForTimeout(600);

    for (const ch of ['z', 'q', 'x', 'v']) {
      await page.keyboard.type(ch);
      await page.waitForTimeout(450);
      steps.push({ pressed: ch, field: await value() });
    }
    for (let i = 0; i < 2; i++) {
      await page.keyboard.press('Backspace');
      await page.waitForTimeout(450);
      steps.push({ pressed: 'Backspace', field: await value() });
    }

    return { view: label, expected: 'zq', steps };
  };

  await page.reload();
  await page.waitForTimeout(4000);
  const now = await run('Şimdi');

  // Clear by reloading, then switch to the grid view: the switch anchors the
  // right end of the toolbar line.
  await page.reload();
  await page.waitForTimeout(4000);
  await page.mouse.click(1379, 46);
  await page.waitForTimeout(1200);
  const grid = await run('Zaman');

  return [now, grid];
}
