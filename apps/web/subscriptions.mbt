///|
fn subscriptions(dispatch : @rabbita.Dispatch[Msg], model : Model) -> @sub.Sub {
  if model.boot_requested {
    return @sub.none
  }
  @sub.custom_sub(
    "bootstrap",
    Local,
    ScheduleBootstrap(dispatch(Bootstrap)),
    SubLoader((payload, scheduler) => {
      match payload {
        ScheduleBootstrap(cmd) => {
          scheduler.add(cmd)
          None
        }
        _ => None
      }
    }),
  )
}
