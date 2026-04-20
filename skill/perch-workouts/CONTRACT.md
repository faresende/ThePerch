# Contract for `perch-workouts`

This skill reads and writes the following in Supabase. If you swap in a non-default data source (via a `providers/` adapter or your own scripts), make sure your writes still conform to this contract — that's what the iOS app expects.

## Table(s)

**records**

## Logical grouping

- `category` = `workouts`
- `type` ∈ `workout_session`

## Payload shape

See [`SKILL.md`](./SKILL.md) → *Data Schema* section for the exact `data` JSON keys, units, and required vs. optional fields.

## Display hints used

See [`SKILL.md`](./SKILL.md) → *Display Hints* table for which `display_hint` values the iOS app expects for each `type`.

## RLS and ownership

- Writes must always set `user_id` to the owning user's UUID.
- Writes are done with the Supabase service role key, which bypasses RLS.
- Reads from the iOS app are constrained by `auth.uid() = user_id` RLS policies — so if a record has the wrong `user_id`, the user won't see it.

## Backward compatibility

If you change the payload shape in a breaking way, update `SKILL.md` and `CONTRACT.md` together. The iOS app tolerates missing optional fields but will silently drop records where required fields are absent.
