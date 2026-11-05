// GET /.well-known/apple-app-site-association: lets Apple send the Message Filter extension's queries
// to this host. Apple's Message Filter docs say to set up shared credentials "substituting messagefilter
// for webcredentials", and Supporting associated domains gives the file's place and the
// "<Application Identifier Prefix>.<Bundle Identifier>" form of the ids. The app and the extension both
// carry the messagefilter: entitlement (ios/project.yml), so both are listed. The team ID is public.

import { json } from "./http";

const TEAM_ID = "CTK4XXPWH9";
const APP = "com.sagochiko.mimamori";

export function siteAssociation(): Response {
  return json({ messagefilter: { apps: [`${TEAM_ID}.${APP}`, `${TEAM_ID}.${APP}.MessageFilter`] } });
}
