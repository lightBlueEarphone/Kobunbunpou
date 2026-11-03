create or replace function public.submit_quiz_answers(
  p_attempt_id uuid,
  p_user_id uuid,
  p_selected_indices integer[],
  p_correct_indices integer[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_attempt public.quiz_attempts%rowtype;
  v_position integer;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
begin
  if p_attempt_id is null or p_user_id is null
     or coalesce(array_length(p_selected_indices, 1), 0) <> 10
     or coalesce(array_length(p_correct_indices, 1), 0) <> 10 then
    raise exception 'Invalid quiz batch';
  end if;

  if exists (
    select 1
    from generate_subscripts(p_selected_indices, 1) as i
    where p_selected_indices[i] not between 0 and 3
       or p_correct_indices[i] not between 0 and 3
  ) then
    raise exception 'Invalid quiz answer index';
  end if;

  select * into v_attempt
  from public.quiz_attempts
  where id = p_attempt_id
    and user_id = p_user_id
  for update;

  if not found then
    raise exception 'Quiz attempt not found';
  end if;
  if v_attempt.status <> 'in_progress' or v_attempt.current_position <> 0 then
    raise exception 'Quiz attempt is not available for batch submission';
  end if;
  if cardinality(v_attempt.question_indices) <> 10 then
    raise exception 'Invalid quiz attempt questions';
  end if;

  -- Each call runs in the same PostgreSQL transaction. Any failure rolls back the full batch.
  for v_position in 0..9 loop
    v_result := to_jsonb(public.submit_quiz_answer(
      p_attempt_id,
      p_user_id,
      v_position,
      p_selected_indices[v_position + 1],
      p_correct_indices[v_position + 1]
    ));
    v_results := v_results || jsonb_build_array(v_result);
  end loop;

  return jsonb_build_object(
    'answers', v_results,
    'final', v_results -> 9
  );
end;
$$;

revoke all on function public.submit_quiz_answers(uuid, uuid, integer[], integer[]) from public;
revoke all on function public.submit_quiz_answers(uuid, uuid, integer[], integer[]) from anon;
revoke all on function public.submit_quiz_answers(uuid, uuid, integer[], integer[]) from authenticated;
grant execute on function public.submit_quiz_answers(uuid, uuid, integer[], integer[]) to service_role;
