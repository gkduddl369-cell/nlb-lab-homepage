import puppeteer from 'puppeteer';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const url = process.argv[2] || 'http://localhost:3000';

(async () => {
    console.log(`Taking screenshot of ${url}...`);
    
    const browser = await puppeteer.launch({
        headless: 'new',
        args: ['--no-sandbox', '--disable-setuid-sandbox']
    });
    
    const page = await browser.newPage();
    
    // Desktop screenshot
    await page.setViewport({ width: 1920, height: 1080 });
    await page.goto(url, { waitUntil: 'networkidle0' });
    await page.screenshot({ 
        path: path.join(__dirname, 'screenshot-desktop.png'),
        fullPage: true 
    });
    console.log('✅ Desktop screenshot saved: screenshot-desktop.png');
    
    // Mobile screenshot
    await page.setViewport({ width: 375, height: 667 });
    await page.goto(url, { waitUntil: 'networkidle0' });
    await page.screenshot({ 
        path: path.join(__dirname, 'screenshot-mobile.png'),
        fullPage: true 
    });
    console.log('✅ Mobile screenshot saved: screenshot-mobile.png');
    
    await browser.close();
    console.log('Done!');
})();
