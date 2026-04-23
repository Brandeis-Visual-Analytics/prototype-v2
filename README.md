How to test:

You may need to go to the Privacy & Security setting to turn on Developer Mode
1. Download project as zip file from this repository.
2. Open Xcode and select project, make sure you select prototype-v2-main and not HapticPrototype when you open the project.
3. In Xcode, you might have to go to “Frameworks, Libraries…” and add “CoreHaptics.framework” if asked to do so.
4. Navigate to HapticTestApp and type the name of the file you want to test:
   ```markdown
      WindowGroup {
            ContinuousPieHapticView() //change name here
        }
   
6. Connect your iPhone to your Mac (you may need to use a USB-C cable to do that) and press run.

You may also be asked to trust the developer on your phone (Settings → General → VPN & Device Management) after you click run. 
