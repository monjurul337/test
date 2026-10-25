/**
 * Shared constants for Chrome Extension
 */

export const CONFIG_KEYS = {
  SESSION_ID: 'sessionId',
  PAIRING_CODE: 'pairingCode',
  SERVER_URL: 'serverUrl',
  BOT_ACTIVE: 'botActive',
  CHECK_INTERVAL: 'checkInterval',
  MISSION: 'mission',
  IVAC_CENTER: 'ivacCenter',
  VISA_TYPE: 'visaType',
  VISA_CATEGORY: 'visaCategory',
  PREFERRED_DATES: 'preferredDates',
  GAP_TIMING: 'gapTiming',
  PROFILES: 'profiles',
  ACTIVE_PROFILE: 'activeProfile',
  OTP_BUFFER: 'otpBuffer',
  LOG_ENTRIES: 'logEntries',
  AUTO_CONFIRM: 'autoConfirm',
};

export const DEFAULT_CONFIG = {
  [CONFIG_KEYS.SERVER_URL]: 'http://localhost:3000',
  [CONFIG_KEYS.BOT_ACTIVE]: false,
  [CONFIG_KEYS.CHECK_INTERVAL]: 20,
  [CONFIG_KEYS.MISSION]: 'Kolkata',
  [CONFIG_KEYS.IVAC_CENTER]: 'Dhaka',
  [CONFIG_KEYS.VISA_TYPE]: 'Tourist',
  [CONFIG_KEYS.VISA_CATEGORY]: 'Individual',
  [CONFIG_KEYS.PREFERRED_DATES]: [],
  [CONFIG_KEYS.GAP_TIMING]: 3000,
  [CONFIG_KEYS.PROFILES]: [],
  [CONFIG_KEYS.ACTIVE_PROFILE]: null,
  [CONFIG_KEYS.OTP_BUFFER]: [],
  [CONFIG_KEYS.LOG_ENTRIES]: [],
  [CONFIG_KEYS.AUTO_CONFIRM]: true,
};

export const WS_MSG = {
  EXTENSION_CONNECT: 'extension_connect',
  ANDROID_CONNECT: 'android_connect',
  OTP: 'otp',
  PING: 'ping',
  PONG: 'pong',
};

export const IVAC_MISSIONS = [
  'Kolkata', 'Delhi', 'Mumbai', 'Chennai', 'Agartala',
  'Guwahati', 'Agra', 'Chandigarh', 'Hyderabad', 'Bangalore',
];

export const IVAC_CENTERS = {
  'Dhaka': ['Uttara', 'Motijheel', 'Dhanmondi'],
  'Chittagong': ['Agrabad'],
  'Sylhet': ['Sylhet City'],
  'Rajshahi': ['Rajshahi City'],
  'Khulna': ['Khulna City'],
  'Mymensingh': ['Mymensingh City'],
};

export const VISA_TYPES = ['Tourist', 'Business', 'Medical', 'Student', 'Employment', 'Conference'];
export const VISA_CATEGORIES = ['Individual', 'Group', 'Journalist'];

export const PORTAL_URL = 'https://appointment.ivacbd.com';

export const PAGE_STATES = {
  HOME: 'home',
  MISSION_SELECT: 'mission_select',
  FORM_FILL: 'form_fill',
  PDF_UPLOAD: 'pdf_upload',
  DATE_SELECT: 'date_select',
  OTP_INPUT: 'otp_input',
  CONFIRM: 'confirm',
  SUCCESS: 'success',
  UNKNOWN: 'unknown',
};
