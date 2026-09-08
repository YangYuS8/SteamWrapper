import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { site, base } from './site.config.mjs';

export default defineConfig({
  site,
  base,
  trailingSlash: 'always',
  output: 'static',
  integrations: [
    starlight({
      title: { en: 'SteamWrapper Docs', 'zh-CN': 'SteamWrapper 文档' },
      description: 'Configure a game once, then launch it normally from Steam.',
      logo: { src: './public/favicon.svg', replacesTitle: false },
      favicon: '/favicon.svg',
      defaultLocale: 'root',
      locales: {
        root: { label: 'English', lang: 'en' },
        'zh-cn': { label: '简体中文', lang: 'zh-CN' },
      },
      social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/YangYuS8/SteamWrapper' }],
      editLink: { baseUrl: 'https://github.com/YangYuS8/SteamWrapper/edit/v2/docs/' },
      customCss: ['./src/styles/custom.css'],
      sidebar: [
        { slug: 'index' },
        {
          label: 'Using SteamWrapper', translations: { 'zh-CN': '使用指南' },
          items: [
            'guides/getting-started', 'guides/installation', 'guides/configuration',
            'guides/wait-modes', 'guides/translated-games', 'guides/troubleshooting',
          ],
        },
        {
          label: 'Development', translations: { 'zh-CN': '开发指南' },
          items: [
            'development/windows', 'development/architecture', 'development/stack',
            'development/testing', 'development/distribution', 'development/documentation',
          ],
        },
        {
          label: 'Project', translations: { 'zh-CN': '项目资料' }, collapsed: true,
          items: [
            'project/roadmap', 'project/design/windows-v2',
            {
              label: 'Decisions', translations: { 'zh-CN': '技术决策' }, collapsed: true,
              items: ['project/decisions/winui3', 'project/decisions/manager-comparison', 'project/decisions/astra-instructions'],
            },
            {
              label: 'Validation records', translations: { 'zh-CN': '验证记录' }, collapsed: true,
              items: ['project/validation/winui', 'project/validation/steam'],
            },
          ],
        },
      ],
    }),
  ],
});
