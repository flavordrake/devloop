# Mobile Touch Constraints

Learnings from device testing that aren't documented in any spec.

## Textarea/input elements intercept touch

Mobile browsers (Android Chrome, iOS Safari) handle touch events on `<textarea>` and
`<input>` elements at the compositor level for text selection, scrolling, and cursor
placement. JavaScript touch handlers (`touchstart`, `touchmove`, `touchend`) fire but
the browser's native behavior takes priority. Even `passive: false` + `preventDefault()`
cannot reliably override this.

**Rule:** Don't use swipe gestures on textarea/input elements for custom behavior.
Use dedicated buttons instead. Swipe gestures work fine on non-interactive elements
(divs, canvas, etc.).

## Scrollable overlays need touch isolation

Scrollable elements (`overflow-y: auto/scroll`) that overlap gesture-handling parents
will leak touch events upward. The parent's swipe/scroll handler claims the gesture
before the overlay can scroll.

**Fix pattern:**
```css
.scrollable-overlay {
  touch-action: pan-y;
  overscroll-behavior: contain;
}
```
Plus `e.stopPropagation()` on `touchmove` in JS if CSS alone isn't sufficient.

## Touch-action: manipulation

Elements with both tap and touch handlers need `touch-action: manipulation` to
disable the 300ms tap delay on mobile. Without it, adding a `touchstart` listener
causes the browser to delay `click` events.

## Position: fixed for scrollable menus

Absolutely-positioned menus that grow upward (`bottom: calc(...)`) can overflow
above the viewport with no scroll. Use `position: fixed` with both `top` and `bottom`
constraints so the browser knows the available scroll area.
