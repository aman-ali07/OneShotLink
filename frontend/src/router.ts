import { nextTick } from "vue";
import { createRouter, createWebHashHistory } from "vue-router";
import ConcealView from "@/views/ConcealView.vue";
import NotFoundView from "@/views/NotFoundView.vue";
import RevealView from "@/views/RevealView.vue";
import SignInView from "@/views/SignInView.vue";
import SignUpView from "@/views/SignUpView.vue";
import DashboardView from "@/views/DashboardView.vue";
import RequestView from "@/views/RequestView.vue";

export const router = createRouter({
  // Secret ids live in the fragment, which browsers never send to the server.
  // Render's CDN therefore logs only "/" instead of the bearer capability.
  history: createWebHashHistory(),
  routes: [
    { path: "/", name: "conceal", component: ConcealView, meta: { title: "New secret" } },
    { path: "/secret/:key", name: "reveal", component: RevealView, meta: { title: "Open a secret" } },
    { path: "/signin", name: "signin", component: SignInView, meta: { title: "Sign in" } },
    { path: "/signup", name: "signup", component: SignUpView, meta: { title: "Create account" } },
    { path: "/dashboard", name: "dashboard", component: DashboardView, meta: { title: "Your account" } },
    { path: "/request/:key", name: "request", component: RequestView, meta: { title: "Send a secret" } },
    { path: "/:pathMatch(.*)*", name: "not-found", component: NotFoundView, meta: { title: "Page not found" } },
  ],
  scrollBehavior() {
    return { top: 0 };
  },
});

// Each route owns a title so tabs, history entries and screen readers can tell
// a reveal link apart from the dashboard or a gone secret (WCAG 2.4.2).
router.afterEach((to) => {
  const title = typeof to.meta.title === "string" ? to.meta.title : "OneShotLink";
  document.title = `${title} · OneShotLink`;
  // Route changes replace the view but leave focus on <body>. Move it to the
  // programmatically focusable main landmark (WCAG 2.4.3). View-level terminal
  // focus runs after async work and still wins when a reveal/receipt completes.
  void nextTick(() => document.getElementById("main")?.focus());
});
