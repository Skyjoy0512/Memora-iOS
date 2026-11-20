import React, {useId, useLayoutEffect, useRef} from 'react';
import {defineRegistry} from '@json-render/react';
import {shadcnComponents} from '@json-render/shadcn';
import {catalog} from './catalog.mjs';
const Metric=({props})=><section className="metric"><p>{props.label}</p><strong>{props.value}</strong>{props.detail&&<p>{props.detail}</p>}</section>;
const BarChart=({props})=>{
  const values=props.items.map(item=>item.value);
  const magnitude=Math.max(...values.map(Math.abs), Number.MIN_VALUE);
  const hasNegative=values.some(value=>value<0);
  const hasPositive=values.some(value=>value>0);
  const zero=hasNegative ? (hasPositive ? 50 : 100) : 0;
  const span=hasNegative && hasPositive ? 50 : 100;
  const formatter=new Intl.NumberFormat('ja-JP',{maximumSignificantDigits:21});
  return <section>
    <h3>{props.title}</h3>
    <dl>{props.items.map((item,index)=>{
      const width=Math.abs(item.value)/magnitude*span;
      return <div key={index} className="chart-row">
        <dt>{item.label}</dt>
        <dd>
          <div aria-hidden="true" className="chart-track" style={{'--zero':zero+'%'}}>
            <div className="chart-bar" style={{insetInlineStart:(item.value<0 ? zero-width : zero)+'%',width:width+'%'}}/>
          </div>
          <span>{formatter.format(item.value)}{props.unit ? ' '+props.unit : ''}</span>
        </dd>
      </div>;
    })}</dl>
  </section>;
};
const Panel=({props,children,slots})=><section aria-label={props.label??undefined} className="panel">{slots?.header&&<header>{slots.header}</header>}{children}{slots?.footer&&<footer>{slots.footer}</footer>}</section>;

function namedField(Component, fallback, controlRole) {
  return function NamedField({props, ...context}) {
    const id = useId();
    const field = useRef(null);
    const label = (props.label || '').trim() || (props.placeholder || '').trim() || fallback;

    useLayoutEffect(() => {
      if (!controlRole) return;
      // These upstream components render a visible label without linking it
      // to the Radix trigger, group, or thumb that receives focus.
      const visibleLabel = field.current?.querySelector('label');
      const control = field.current?.querySelector(`[role="${controlRole}"]`);
      if (visibleLabel && control) {
        visibleLabel.id = `${id}-label`;
        control.setAttribute('aria-labelledby', visibleLabel.id);
      }
    });

    // A spec can omit a name or reuse it inside a repeated item. The mounted
    // field owns its DOM id. The JSON spec's state paths stay on the bindings.
    const rendered = <Component {...context} props={{...props, name: id, label}}/>;
    return controlRole ? <div ref={field}>{rendered}</div> : rendered;
  };
}

const formComponents = {
  Input: namedField(shadcnComponents.Input, '入力'),
  Textarea: namedField(shadcnComponents.Textarea, '複数行の入力'),
  Select: namedField(shadcnComponents.Select, '選択', 'combobox'),
  Checkbox: namedField(shadcnComponents.Checkbox, 'チェックボックス'),
  Radio: namedField(shadcnComponents.Radio, '選択肢', 'radiogroup'),
  Switch: namedField(shadcnComponents.Switch, '切り替え'),
  Slider: namedField(shadcnComponents.Slider, '値', 'slider'),
};

export const {registry}=defineRegistry(catalog,{
  components:{...shadcnComponents,...formComponents,Metric,BarChart,Panel}
});

