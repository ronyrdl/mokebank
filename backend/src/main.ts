import { createApp } from './app.js';
import { integerSetting } from './common/config.js';

const app = await createApp();
app.enableShutdownHooks();
await app.listen(integerSetting('PORT', 3000), '0.0.0.0');
