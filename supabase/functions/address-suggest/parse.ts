// Turn a Places API (New) addressComponents list into the four fields the
// pipeline already stores. There is no postcode or state column; those
// components are read only to recognise the country and then dropped.
//
// Estate is filled only from a `neighborhood` component, and only when that
// name is not the suburb again. Australian housing-estate names are often
// absent from the official street address, so a missing neighborhood means
// "leave Estate alone" (the caller treats null that way).

export interface AddressComponent {
  longText?: string;
  shortText?: string;
  types?: string[];
}

export interface ParsedAddress {
  streetNumber: string;
  streetName: string;
  suburb: string;
  /** Set only when Google returned a distinct neighbourhood / estate name. */
  estate: string | null;
  inAustralia: boolean;
}

const UNIT_PREFIX = /^(?:unit|apt|apartment|flat|suite)\s+/i;

function textOf(c: AddressComponent | undefined, which: "long" | "short"): string {
  if (!c) return "";
  const raw = which === "short" ? (c.shortText || c.longText) : (c.longText || c.shortText);
  return (raw ?? "").replace(/\s+/g, " ").trim();
}

function pick(components: AddressComponent[], type: string, which: "long" | "short" = "long"): string {
  return textOf(components.find((c) => Array.isArray(c.types) && c.types.includes(type)), which);
}

/** "Unit 2" + street number "14" becomes the Australian "2/14". Other short unit labels are kept in front. */
function streetNumber(components: AddressComponent[]): string {
  const number = pick(components, "street_number");
  const sub = pick(components, "subpremise");
  if (!sub) return number;
  const unit = sub.replace(UNIT_PREFIX, "").trim();
  if (number && /^[0-9]+[A-Za-z]?$/.test(unit)) return `${unit}/${number}`;
  if (number && sub.length <= 16) return `${sub}/${number}`;
  return number || sub;
}

export function parseAddressComponents(components: AddressComponent[] | null | undefined): ParsedAddress | null {
  const list = Array.isArray(components) ? components : [];
  if (!list.length) return null;

  const streetName = pick(list, "route");
  const number = streetNumber(list);
  // Council (administrative_area_level_2) and state (level_1) are not suburbs.
  const suburb = pick(list, "locality")
    || pick(list, "postal_town")
    || pick(list, "sublocality_level_1")
    || pick(list, "sublocality");

  const neighborhood = pick(list, "neighborhood");
  const estate = neighborhood && neighborhood.toLowerCase() !== suburb.toLowerCase()
    ? neighborhood
    : null;

  const countryShort = pick(list, "country", "short");
  const countryLong = pick(list, "country", "long");
  const inAustralia = !countryShort && !countryLong
    ? true
    : countryShort.toUpperCase() === "AU" || countryLong.toLowerCase() === "australia";

  if (!number && !streetName && !suburb) return null;
  return { streetNumber: number, streetName, suburb, estate, inAustralia };
}
