///|
fn main {
  let (dispatch, root) = @rabbita.cell_with_dispatch(
    model=initial_admin_model(),
    update~,
    view~,
    subscriptions~,
  )
  ignore(dispatch)
  @rabbita.new(root).mount("app")
}
