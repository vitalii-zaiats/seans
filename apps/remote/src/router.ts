/**
 * Two routes, and one of them is an apology.
 *
 * `/r/:code` is the whole app. Everything else is somebody who typed the host
 * without the code, or followed a link that lost its tail — and the honest
 * answer to that is a sentence, not a redirect to a page that would have to
 * ask them for a code they do not have.
 */

import { createRouter, createWebHistory } from 'vue-router'

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    {
      path: '/r/:code',
      name: 'pair',
      component: () => import('@/views/PairView.vue'),
      // As a prop rather than read off the route inside the view: the code is
      // an input to that page, and a component that takes its input as an
      // argument is one that can be looked at on its own.
      props: true,
    },
    {
      path: '/:rest(.*)*',
      name: 'nowhere',
      component: () => import('@/views/NowhereView.vue'),
    },
  ],
})
