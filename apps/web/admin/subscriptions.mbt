///|
priv suberror AdminBootstrapSubscription {
  ScheduleAdminBootstrap(@rabbita.Cmd)
}

///|
fn subscriptions(
  dispatch : @rabbita.Dispatch[AdminMsg],
  model : AdminModel,
) -> @sub.Sub {
  if model.boot_requested {
    return @sub.none
  }
  @sub.custom_sub(
    "admin-bootstrap",
    Local,
    ScheduleAdminBootstrap(dispatch(Bootstrap)),
    SubLoader((payload, scheduler) => {
      match payload {
        ScheduleAdminBootstrap(cmd) => {
          scheduler.add(cmd)
          None
        }
        _ => None
      }
    }),
  )
}
