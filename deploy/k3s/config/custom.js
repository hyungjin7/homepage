// 화면용 스크립트: 끌어서 놓기(drag & drop)로 그룹·카드 순서 바꾸기.
// - 오른쪽 아래 "배치 편집" → 그룹 제목줄이나 카드를 끌어 같은 줄 안에서 옮김 → "완료".
// - 순서는 이 브라우저에만 저장됨(localStorage). 모두에게 같게 하려면 "설정 복사" 내용을 저장소에 반영.
// - 화면 요소를 옮기지 않고 CSS order 만 바꿔서, Homepage 가 화면을 다시 그려도 깨지지 않음.
(function () {
  if (window.__dlvOrder) return;
  window.__dlvOrder = true;

  var KEY = "dlv-homepage-order-v1";
  var editing = false;
  var dragEl = null;

  function load() {
    try {
      var v = JSON.parse(localStorage.getItem(KEY) || "{}");
      return { groups: v.groups || [], cards: v.cards || {} };
    } catch (e) {
      return { groups: [], cards: {} };
    }
  }
  function save(state) {
    try {
      localStorage.setItem(KEY, JSON.stringify(state));
    } catch (e) {}
  }

  function groupBoxes() {
    var out = [];
    ["layout-groups", "services"].forEach(function (id) {
      var box = document.getElementById(id);
      if (box) out.push(box);
    });
    return out;
  }
  function groupsIn(box) {
    return Array.prototype.filter.call(box.children, function (el) {
      return el.classList.contains("services-group");
    });
  }
  function groupName(el) {
    var h = el.querySelector(":scope > * .service-group-name, .service-group-name");
    return h ? h.textContent.trim() : "";
  }
  function cardsIn(list) {
    return Array.prototype.filter.call(list.children, function (el) {
      return el.classList.contains("service");
    });
  }
  function cardName(el) {
    return el.getAttribute("data-name") || "";
  }
  function topList(group) {
    // 그룹 바로 아래 카드 목록(하위 그룹 것은 제외)
    var lists = group.querySelectorAll("ul.services-list");
    for (var i = 0; i < lists.length; i++) {
      if (lists[i].closest(".services-group") === group) return lists[i];
    }
    return null;
  }

  // 저장한 순서를 CSS order 로 입힘. 저장에 없는 것은 원래 순서대로 뒤에 붙음.
  function orderEls(els, names, nameOf) {
    els.forEach(function (el, i) {
      var idx = names.indexOf(nameOf(el));
      el.style.order = String(idx >= 0 ? idx : 1000 + i);
    });
  }
  function currentOrder(els, nameOf) {
    return els
      .slice()
      .sort(function (a, b) {
        return (Number(a.style.order) || 0) - (Number(b.style.order) || 0);
      })
      .map(nameOf);
  }

  function apply() {
    var st = load();
    groupBoxes().forEach(function (box) {
      var groups = groupsIn(box);
      orderEls(groups, st.groups, groupName);
      groups.forEach(function (g) {
        var list = topList(g);
        if (list) orderEls(cardsIn(list), st.cards[groupName(g)] || [], cardName);
        if (editing) {
          g.setAttribute("draggable", "true");
          if (list)
            cardsIn(list).forEach(function (c) {
              c.setAttribute("draggable", "true");
            });
        }
      });
    });
    document.querySelectorAll(".services-group a, .services-group img").forEach(function (a) {
      if (editing) a.setAttribute("draggable", "false");
      else a.removeAttribute("draggable");
    });
    if (!editing) {
      document.querySelectorAll(".services-group[draggable], .service[draggable]").forEach(function (el) {
        el.removeAttribute("draggable");
      });
    }
  }

  // 끌어 놓은 자리 계산: 놓은 카드(그룹)의 앞/뒤 중 가까운 쪽
  function dropTo(target, e) {
    if (!dragEl || target === dragEl || target.parentNode !== dragEl.parentNode) return;
    var isCard = dragEl.classList.contains("service");
    var siblings = isCard ? cardsIn(dragEl.parentNode) : groupsIn(dragEl.parentNode);
    var nameOf = isCard ? cardName : groupName;
    var names = currentOrder(siblings, nameOf);
    var from = nameOf(dragEl);
    names.splice(names.indexOf(from), 1);
    var r = target.getBoundingClientRect();
    var after = isCard ? e.clientX > r.left + r.width / 2 : e.clientY > r.top + r.height / 2;
    var at = names.indexOf(nameOf(target)) + (after ? 1 : 0);
    names.splice(at, 0, from);

    var st = load();
    if (isCard) {
      st.cards[groupName(dragEl.closest(".services-group"))] = names;
    } else {
      // 두 칸(#layout-groups·#services)의 그룹을 한 목록으로 저장
      var others = st.groups.filter(function (n) {
        return names.indexOf(n) < 0;
      });
      st.groups = names.concat(others);
    }
    save(st);
    apply();
  }

  document.addEventListener(
    "dragstart",
    function (e) {
      if (!editing) return;
      var el = e.target.closest && e.target.closest(".service[draggable], .services-group[draggable]");
      if (!el) return;
      e.stopPropagation();
      dragEl = el;
      el.classList.add("dlv-dragging");
      try {
        e.dataTransfer.effectAllowed = "move";
        e.dataTransfer.setData("text/plain", "");
      } catch (err) {}
    },
    true,
  );
  function targetOf(e) {
    if (!dragEl || !e.target.closest) return null;
    var sel = dragEl.classList.contains("service") ? ".service" : ".services-group";
    var t = e.target.closest(sel);
    // 하위 그룹 안의 같은 종류가 아니라 같은 부모를 가진 것만
    while (t && t.parentNode !== dragEl.parentNode) t = t.parentNode.closest && t.parentNode.closest(sel);
    return t;
  }
  document.addEventListener("dragover", function (e) {
    if (!editing || !dragEl) return;
    var t = targetOf(e);
    if (t) e.preventDefault();
  });
  document.addEventListener("drop", function (e) {
    if (!editing || !dragEl) return;
    var t = targetOf(e);
    if (t) {
      e.preventDefault();
      dropTo(t, e);
    }
  });
  document.addEventListener("dragend", function () {
    if (dragEl) dragEl.classList.remove("dlv-dragging");
    dragEl = null;
  });
  // 편집 중에는 카드를 눌러도 사이트로 가지 않고, 그룹이 접히지 않음
  document.addEventListener(
    "click",
    function (e) {
      if (!editing || !e.target.closest) return;
      if (e.target.closest("#dlv-order-bar")) return;
      if (e.target.closest(".services-group")) {
        e.preventDefault();
        e.stopPropagation();
      }
    },
    true,
  );

  function copyText() {
    var lines = ["# settings.yaml layout 순서 (위에서부터)"];
    var groups = [];
    groupBoxes().forEach(function (box) {
      groups = groups.concat(currentOrder(groupsIn(box), groupName));
    });
    lines.push(groups.join(" → "));
    lines.push("", "# ingress-cards.sh 순서 칸 (작을수록 앞)");
    groupBoxes().forEach(function (box) {
      groupsIn(box).forEach(function (g) {
        var list = topList(g);
        if (!list) return;
        var names = currentOrder(cardsIn(list), cardName);
        lines.push(
          groupName(g) +
            ": " +
            names
              .map(function (n, i) {
                return n + "=" + (i + 1) * 10;
              })
              .join(", "),
        );
      });
    });
    var text = lines.join("\n");
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(
        function () {
          alert("복사됨. 대화창에 붙여 넣으면 저장소에 반영해 드림.\n\n" + text);
        },
        function () {
          prompt("아래 내용을 복사하세요", text);
        },
      );
    } else {
      prompt("아래 내용을 복사하세요", text);
    }
  }

  function button(label, onClick) {
    var b = document.createElement("button");
    b.type = "button";
    b.textContent = label;
    b.addEventListener("click", onClick);
    return b;
  }
  function render(bar) {
    bar.innerHTML = "";
    if (!editing) {
      bar.appendChild(
        button("배치 편집", function () {
          editing = true;
          document.body.classList.add("dlv-editing");
          render(bar);
          apply();
        }),
      );
      return;
    }
    var tip = document.createElement("span");
    tip.textContent = "끌어서 옮기기 (같은 줄 안에서)";
    bar.appendChild(tip);
    bar.appendChild(button("설정 복사", copyText));
    bar.appendChild(
      button("처음대로", function () {
        if (!confirm("이 브라우저에 저장한 순서를 지우고 원래대로 돌릴까요?")) return;
        save({ groups: [], cards: {} });
        apply();
      }),
    );
    bar.appendChild(
      button("완료", function () {
        editing = false;
        document.body.classList.remove("dlv-editing");
        render(bar);
        apply();
      }),
    );
  }

  function init() {
    if (!document.getElementById("dlv-order-bar")) {
      var bar = document.createElement("div");
      bar.id = "dlv-order-bar";
      document.body.appendChild(bar);
      render(bar);
    }
    apply();
    var t = null;
    new MutationObserver(function () {
      clearTimeout(t);
      t = setTimeout(apply, 100);
    }).observe(document.body, { childList: true, subtree: true });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
