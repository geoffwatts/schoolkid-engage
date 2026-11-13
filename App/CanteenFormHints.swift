import Foundation
import WebKit
import CanteenKit

/// Fills in what My Student Account's top-up forms leave out, so iOS treats them like well-made payment forms: card
/// fields get `autocomplete` types (which is what makes iOS offer saved cards above the keyboard; MSA even sets the
/// card number to `autocomplete="off"`) and the recharge amount gets a decimal keypad. It only sets attributes; it
/// never reads or sends anything typed into the page.
enum CanteenFormHints {
    static func script(portal: MSAPortal) -> WKUserScript {
        let host = (try? String(data: JSONEncoder().encode(portal.host), encoding: .utf8)) ?? "\"\""
        let source = """
        (function () {
          var here = location.hostname.toLowerCase();
          // The portal and MSA's own payment pages only; never the identity provider's sign-in.
          if (here !== \(host) && !/(^|\\.)mystudentaccount\\.com$/.test(here)) return;
          // MSA's own field names (Account/Recharge, then Process Payment), as of portal version 2.39.
          var known = {
            rechargeamount: [null, 'decimal'],
            cardnumber: ['cc-number', 'numeric'],
            cardname: ['cc-name', null],
            cardexpiry: ['cc-exp', 'numeric'],
            cardcvc: ['cc-csc', 'numeric']
          };
          // Otherwise, by what the field says about itself (a combined expiry before month or year alone).
          var rules = [
            [/card.?holder|name.?on.?card|cc.?name|card.?name/, 'cc-name', null],
            [/card.?(no|num)|cc.?(no|num)|cardnumber|\\bpan\\b/, 'cc-number', 'numeric'],
            [/mm.?\\/.?yy|expir\\w* date|exp.?date|card.?expiry/, 'cc-exp', 'numeric'],
            [/exp\\w*.?(month|mm)\\b|^mm$/, 'cc-exp-month', 'numeric'],
            [/exp\\w*.?(year|yy)|^yy(yy)?$/, 'cc-exp-year', 'numeric'],
            [/cvv|cvc|csc|security.?code|card.?code|card.?verification/, 'cc-csc', 'numeric'],
            [/amount|top.?up|recharge/, null, 'decimal']
          ];
          function describe(field) {
            var parts = [field.name, field.id, field.getAttribute('placeholder'), field.getAttribute('aria-label')];
            var label = field.closest('label') || (field.id && document.querySelector('label[for="' + CSS.escape(field.id) + '"]'));
            if (label) parts.push(label.textContent);
            return parts.filter(Boolean).join(' ').toLowerCase().replace(/\\s+/g, ' ').trim();
          }
          function hintsFor(field) {
            var exact = known[(field.name || field.id || '').toLowerCase()];
            if (exact) return exact;
            var text = describe(field);
            if (!text) return null;
            for (var r = 0; r < rules.length; r++) if (rules[r][0].test(text)) return [rules[r][1], rules[r][2]];
            return null;
          }
          function hint() {
            var fields = document.querySelectorAll('input:not([type=hidden]):not([type=checkbox]):not([type=radio]):not([type=submit]):not([type=button]), select');
            for (var i = 0; i < fields.length; i++) {
              var field = fields[i], hints = hintsFor(field);
              if (!hints) continue;
              var changed = false;
              if (hints[0] && field.getAttribute('autocomplete') !== hints[0]) { field.setAttribute('autocomplete', hints[0]); changed = true; }
              if (hints[1] && field.tagName === 'INPUT' && field.getAttribute('inputmode') !== hints[1]) { field.setAttribute('inputmode', hints[1]); changed = true; }
              // An autofocused field already has its keyboard; focus it again so the new keyboard and suggestions show.
              if (changed && document.activeElement === field) { field.blur(); field.focus(); }
            }
          }
          hint();
          // The payment form is drawn by AngularJS after load.
          var pending = false;
          new MutationObserver(function () {
            if (pending) return;
            pending = true;
            setTimeout(function () { pending = false; hint(); }, 50);
          }).observe(document.documentElement, { childList: true, subtree: true });
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }

    /// Focuses the first empty, visible field of the top-up forms (the amount, then the card number), scrolled to the
    /// middle of the screen. True once done, or when there's nothing to do (the user is already in a field).
    static let focusScript = """
    (function () {
      var active = document.activeElement;
      if (active && active !== document.body && /^(INPUT|SELECT|TEXTAREA)$/.test(active.tagName) && active.value) return true;
      var names = ['RechargeAmount', 'CardNumber'];
      for (var i = 0; i < names.length; i++) {
        var field = document.querySelector('input[name="' + names[i] + '"]');
        if (!field || field.offsetParent === null || field.value) continue;
        field.scrollIntoView({ block: 'center' });
        field.focus();
        return true;
      }
      return !document.querySelector('form');
    })();
    """
}
