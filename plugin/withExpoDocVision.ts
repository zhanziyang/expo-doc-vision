import { ConfigPlugin } from "expo/config-plugins";

/**
 * Expo Config Plugin for expo-doc-vision.
 *
 * The Vision framework is available on iOS 13.0+, but this plugin
 * does not override the deployment target since modern React Native
 * and Expo already require iOS 15.1+.
 *
 * No special permissions are required for Vision OCR.
 */
const withExpoDocVision: ConfigPlugin = (config) => {
  // No modifications needed - Vision framework is available on iOS 13.0+
  // and modern React Native/Expo already require iOS 15.1+
  return config;
};

export default withExpoDocVision;
