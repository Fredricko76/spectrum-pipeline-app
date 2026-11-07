// Address suggestions for the client form. See handler.ts for the contract
// and supabase/ADDRESS_SUGGEST.md for the secret and the Google Cloud setup.
// This file only starts the server so tests can import the handler without
// listening on a port.
import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";
import { handleAddressSuggest } from "./handler.ts";

Deno.serve(handleAddressSuggest);
