import { createRouter, createWebHistory } from "vue-router";
import ConcealView from "@/views/ConcealView.vue";
import NotFoundView from "@/views/NotFoundView.vue";
import RevealView from "@/views/RevealView.vue";
import SignInView from "@/views/SignInView.vue";
import SignUpView from "@/views/SignUpView.vue";
import DashboardView from "@/views/DashboardView.vue";

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: "/", name: "conceal", component: ConcealView },
    { path: "/secret/:key", name: "reveal", component: RevealView },
    { path: "/signin", name: "signin", component: SignInView },
    { path: "/signup", name: "signup", component: SignUpView },
    { path: "/dashboard", name: "dashboard", component: DashboardView },
    { path: "/:pathMatch(.*)*", name: "not-found", component: NotFoundView },
  ],
  scrollBehavior() {
    return { top: 0 };
  },
});
